#!/usr/bin/env bash
# Shared AUZiX library ownership rules.
#
# Leaf/application packages may depend on the platform substrate, but they must
# not bundle substrate libraries into /Programs/<App>/<Version>/Libraries and
# then win by LD_LIBRARY_PATH. Core/runtime/platform upgrades belong to a base
# release rebuild lane.

auzix_library_basename() {
  basename "$1"
}

auzix_library_policy_class() {
  local base
  base="$(auzix_library_basename "$1")"
  case "${base}" in
    ld-linux*.so*|libc.so*|libm.so*|libpthread.so*|librt.so*|libdl.so*|libutil.so*|libresolv.so*|libnsl.so*|libcrypt.so*|libanl.so*|libthread_db.so*|libgcc_s.so*|libstdc++.so*|libatomic.so*)
      printf 'core-abi\n'
      return 0
      ;;
    libssl.so*|libcrypto.so*|libgnutls.so*|libgcrypt.so*|libgpg-error.so*|libnss3.so*|libnssutil3.so*|libsmime3.so*|libsoftokn3.so*|libfreebl3.so*|libplc4.so*|libplds4.so*|libnspr4.so*)
      printf 'security-abi\n'
      return 0
      ;;
    libX11.so*|libX11-xcb.so*|libXau.so*|libXdmcp.so*|libXext.so*|libXi.so*|libXrender.so*|libXrandr.so*|libXfixes.so*|libXcursor.so*|libXdamage.so*|libXcomposite.so*|libXtst.so*|libxkbcommon.so*|libxcb*.so*|libGL.so*|libEGL.so*|libGLES*.so*|libgbm.so*|libdrm.so*|libwayland-*.so*)
      printf 'graphics-platform\n'
      return 0
      ;;
    libglib-2.0.so*|libgobject-2.0.so*|libgio-2.0.so*|libgmodule-2.0.so*|libgthread-2.0.so*|libgtk-*.so*|libgdk-*.so*|libpango*.so*|libpangocairo*.so*|libatk-*.so*|libcairo*.so*|libfontconfig.so*|libfreetype.so*)
      printf 'desktop-platform\n'
      return 0
      ;;
    libeina.so*|libeet.so*|libevas.so*|libecore*.so*|libedje.so*|libefreet*.so*|libelementary.so*|libeio.so*|libeeze.so*|libemotion.so*|libelput.so*|libeldbus.so*|libethumb*.so*)
      printf 'efl-platform\n'
      return 0
      ;;
  esac
  printf 'app-private\n'
}

auzix_forbid_app_local_library() {
  local class
  class="$(auzix_library_policy_class "$1")"
  [[ "${class}" != "app-private" ]]
}

auzix_copy_app_private_library() {
  local source="$1"
  local target="$2"
  local class
  [[ -e "${source}" ]] || return 0
  class="$(auzix_library_policy_class "${source}")"
  if [[ "${class}" != "app-private" ]]; then
    printf '[auzix-library-policy] substrate-skip class=%s source=%s target=%s\n' "${class}" "${source}" "${target}" >&2
    return 0
  fi
  install -D -m 0755 "${source}" "${target}"
}
