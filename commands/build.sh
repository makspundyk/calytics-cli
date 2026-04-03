#!/bin/bash
# cal build <target>
# Build services, shared modules, or alias shims.
#
# Targets:
#   shared   Sync & build calytics-shared-modules (git fetch + smart branch + build)
#   shims    Build alias shims + patch pino for calytics-be
#   be       Build calytics-be
#   admin    Build calytics-be-admin
#   a2a      Build calytics-a2a

target="${1:-}"
[ -z "$target" ] && fail "Usage: cal build <target> (shared, shims, be, admin, a2a)"

case "$target" in
  shared)
    phase "Sync & build shared modules"

    for mod_dir in "$SHARED_MODULES_DIR"/*/; do
      [ ! -d "$mod_dir/.git" ] && continue
      mod_name=$(basename "$mod_dir")

      [ ! -f "$mod_dir/package.json" ] && continue
      grep -q '"build"' "$mod_dir/package.json" 2>/dev/null || { warn "$mod_name — no build script, skipping"; continue; }

      info "$mod_name — syncing..."

      # Fetch remote
      (cd "$mod_dir" && git fetch origin --quiet 2>/dev/null) || true

      # Branch decision
      current_branch=$(cd "$mod_dir" && git branch --show-current 2>/dev/null)
      if [ -n "$current_branch" ] && [ "$current_branch" != "main" ]; then
        has_uncommitted=$(cd "$mod_dir" && git status --porcelain 2>/dev/null)
        has_local_commits=$(cd "$mod_dir" && git log "@{u}..HEAD" --oneline 2>/dev/null)

        if [ -z "$has_uncommitted" ] && [ -z "$has_local_commits" ]; then
          warn "$mod_name — branch '$current_branch' has no local work, switching to main"
          (cd "$mod_dir" && git checkout main --quiet 2>/dev/null && git pull --ff-only origin main --quiet 2>/dev/null) || true
        else
          ok "$mod_name — staying on '$current_branch' (has local work)"
        fi
      elif [ "$current_branch" = "main" ]; then
        (cd "$mod_dir" && git pull --ff-only origin main --quiet 2>/dev/null) || true
      fi

      # Build decision
      needs_build=false

      # Find dist/ (root or workspace packages)
      dist_dir="$mod_dir/dist"
      if [ ! -d "$dist_dir" ] && [ -d "$mod_dir/packages" ]; then
        dist_dir=$(find "$mod_dir/packages" -maxdepth 2 -name "dist" -type d | head -1)
      fi

      if [ -z "$dist_dir" ] || [ ! -d "$dist_dir" ]; then
        needs_build=true
        info "$mod_name — no dist/, needs build"
      else
        build_marker="$dist_dir/index.js"
        [ ! -f "$build_marker" ] && build_marker="$dist_dir/index.d.ts"
        [ ! -f "$build_marker" ] && build_marker=$(find "$dist_dir" -name "*.js" -type f | head -1)
        if [ -z "$build_marker" ]; then
          needs_build=true
        else
          newer_src=$(find "$mod_dir/src" "$mod_dir/packages" -name "*.ts" -not -name "*.d.ts" -newer "$build_marker" 2>/dev/null | head -1)
          if [ -n "$newer_src" ]; then
            needs_build=true
            info "$mod_name — source changed ($(basename "$newer_src"))"
          fi
        fi
      fi

      if [ "$needs_build" = true ]; then
        info "$mod_name — building..."
        if (cd "$mod_dir" && npm install --silent 2>/dev/null && npm run build 2>&1 | tail -5); then
          ok "$mod_name — built"
        else
          warn "$mod_name — build failed (non-fatal)"
        fi
      else
        ok "$mod_name — up to date"
      fi
    done
    ;;

  shims)
    phase "Building alias shims + patching pino"
    be_dir="$(svc_path be)"
    shim_script="$be_dir/scripts/build-local-alias-shims.sh"
    [ ! -f "$shim_script" ] && fail "Shim script not found: $shim_script"
    (cd "$be_dir" && bash "$shim_script")
    ;;

  be|admin|a2a)
    svc_dir="$(svc_path "$target")"
    label="${SVC_LABEL[$target]}"
    phase "Building $label"
    if [ "$target" = "admin" ]; then
      dist_dir="$svc_dir/dist"
      [ -d "$dist_dir" ] && { sudo rm -rf "$dist_dir" 2>/dev/null || rm -rf "$dist_dir"; }
    fi
    (cd "$svc_dir" && npm run build 2>&1 | tail -5)
    ok "$label built"
    ;;

  *)
    fail "Unknown build target: $target (try: shared, shims, be, admin, a2a)"
    ;;
esac
