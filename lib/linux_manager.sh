#!/usr/bin/env bash

linux_manager_print_banner() {
  printf '%s\n' 'DayZ Server Manager (Linux)'
  printf '%s\n' 'Linux scaffold loaded.'
}

linux_manager_get_config_path() {
  local config_home="${XDG_CONFIG_HOME:-${HOME:-/tmp}/.config}"

  printf '%s\n' "${DAYZ_SERVER_MANAGER_CONFIG_PATH:-${config_home}/dayz-server-manager/server-manager.config.json}"
}

linux_manager_detect_architecture() {
  uname -m
}

linux_manager_get_server_app_id() {
  local server_branch="${1:-stable}"

  case "${server_branch}" in
    stable|"")
      printf '%s\n' '223350'
      ;;
    experimental)
      printf '%s\n' '1042420'
      ;;
    *)
      printf 'unknown server branch: %s\n' "${server_branch}" >&2
      return 1
      ;;
  esac
}

linux_manager_get_workshop_app_id() {
  printf '%s\n' '221100'
}

linux_manager_build_mod_launch_string() {
  local workshop_ids=("$@")
  local launch_string=""
  local workshop_id

  for workshop_id in "${workshop_ids[@]}"; do
    workshop_id="${workshop_id%$'\r'}"
    if [[ -z "${workshop_id}" ]]; then
      continue
    fi

    launch_string+="${workshop_id};"
  done

  printf '%s\n' "${launch_string}"
}

linux_manager_build_server_launch_args() {
  local base_args="${1:-}"
  local mod_launch_string="${2:-}"
  local server_mod_launch_string="${3:-}"
  local launch_args="${base_args}"

  if [[ -n "${mod_launch_string}" ]]; then
    if [[ -n "${launch_args}" ]]; then
      launch_args+=" "
    fi

    launch_args+="\"-mod=${mod_launch_string}\""
  fi

  if [[ -n "${server_mod_launch_string}" ]]; then
    if [[ -n "${launch_args}" ]]; then
      launch_args+=" "
    fi

    launch_args+="\"-serverMod=${server_mod_launch_string}\""
  fi

  printf '%s\n' "${launch_args}"
}

linux_manager_build_config_driven_launch_args() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local profiles_path
  local base_args
  local active_client_mods=()
  local active_server_mods=()
  local client_mod_launch_string
  local server_mod_launch_string

  profiles_path="$(linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    '/srv/dayz/server/profiles' \
    'profilesPath' \
    's/.*"profilesPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')" || return 1

  case "${profiles_path}" in
    *$'\n'*|*$'\r'*|*\"*|*\\*|*" "*)
      printf 'unsafe profiles path: %s\n' "${profiles_path}" >&2
      return 1
      ;;
  esac

  base_args="-config=serverDZ.cfg -profiles=${profiles_path} -port=2302 -freezecheck -adminlog -dologs"

  mapfile -t active_client_mods < <(linux_manager_get_active_client_mods "${config_path}")
  mapfile -t active_server_mods < <(linux_manager_get_active_server_mods "${config_path}")

  client_mod_launch_string="$(linux_manager_build_mod_launch_string "${active_client_mods[@]}")"
  server_mod_launch_string="$(linux_manager_build_mod_launch_string "${active_server_mods[@]}")"

  linux_manager_build_server_launch_args \
    "${base_args}" \
    "${client_mod_launch_string}" \
    "${server_mod_launch_string}"
}

linux_manager_get_workshop_content_root() {
  local server_root="${1:-}"

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  printf '%s\n' "${server_root}/steamapps/workshop/content/$(linux_manager_get_workshop_app_id)"
}

linux_manager_is_valid_workshop_id() {
  local workshop_id="${1:-}"
  workshop_id="${workshop_id%$'\r'}"

  [[ "${workshop_id}" =~ ^[0-9]+$ ]]
}

linux_manager_is_safe_bikey_filename() {
  local filename="${1:-}"
  filename="${filename%$'\r'}"

  [[ -n "${filename}" && "${filename}" != */* && "${filename}" != *\\* && "${filename}" != "." && "${filename}" != ".." && "${filename}" =~ \.bikey$ ]]
}

linux_manager_get_mod_symlink_tracking_path() {
  local server_root="${1:-}"

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  printf '%s\n' "${server_root}/.dayz-server-manager-managed-symlinks"
}

linux_manager_get_mod_bikey_tracking_path() {
  local server_root="${1:-}"

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  printf '%s\n' "${server_root}/keys/.dayz-server-manager-managed-bikeys"
}

linux_manager_write_tracking_file_from_lines() {
  local tracking_path="${1:-}"
  shift || true
  local temp_path

  if [[ -z "${tracking_path}" ]]; then
    printf 'tracking path is required\n' >&2
    return 1
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${tracking_path}")" || return 1

  : > "${temp_path}"
  if [[ "$#" -gt 0 ]]; then
    if ! printf '%s\n' "$@" > "${temp_path}"; then
      rm -f "${temp_path}"
      return 1
    fi
  fi

  if ! mv -f "${temp_path}" "${tracking_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_sync_mod_symlinks() {
  local server_root="${1:-}"
  local workshop_root="${2:-}"
  local active_mod_ids_text="${3:-}"
  local tracking_path
  local current_ids=()
  local current_id
  declare -A current_ids_seen=()
  local old_id
  local old_ids=()

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  if [[ -z "${workshop_root}" ]]; then
    workshop_root="$(linux_manager_get_workshop_content_root "${server_root}")" || return 1
  fi

  mkdir -p "${server_root}"

  tracking_path="$(linux_manager_get_mod_symlink_tracking_path "${server_root}")" || return 1

  while IFS= read -r current_id; do
    current_id="${current_id%$'\r'}"
    [[ -z "${current_id}" ]] && continue

    if ! linux_manager_is_valid_workshop_id "${current_id}"; then
      printf 'unsafe workshop id: %s\n' "${current_id}" >&2
      return 1
    fi

    if [[ -z "${current_ids_seen[$current_id]+x}" ]]; then
      current_ids_seen["$current_id"]=1
      current_ids+=("${current_id}")
    fi
  done <<< "${active_mod_ids_text}"

  if [[ -r "${tracking_path}" ]]; then
    while IFS= read -r old_id; do
      old_id="${old_id%$'\r'}"
      [[ -z "${old_id}" ]] && continue
      old_ids+=("${old_id}")
    done < "${tracking_path}"
  fi

  for current_id in "${current_ids[@]}"; do
    ln -sfn "${workshop_root}/${current_id}" "${server_root}/${current_id}"
  done

  for old_id in "${old_ids[@]}"; do
    if [[ -z "${current_ids_seen[$old_id]+x}" ]]; then
      rm -f "${server_root}/${old_id}"
    fi
  done

  linux_manager_write_tracking_file_from_lines "${tracking_path}" "${current_ids[@]}"
}

linux_manager_lowercase_deployed_path_basename() {
  local path="${1:-}"
  local dir_path
  local base_name
  local lower_name

  if [[ -z "${path}" || ! -e "${path}" ]]; then
    return 0
  fi

  dir_path="$(dirname "${path}")"
  base_name="$(basename "${path}")"
  lower_name="$(printf '%s' "${base_name}" | tr '[:upper:]' '[:lower:]')"

  if [[ "${base_name}" == "${lower_name}" ]]; then
    return 0
  fi

  linux_manager_run_privileged_command mv "${path}" "${dir_path}/${lower_name}"
}

linux_manager_normalize_deployed_mod_directory() {
  local mod_dir="${1:-}"
  local addons_dir
  local keys_dir
  local path
  local addon_entries=()
  local key_entries=()

  if [[ -z "${mod_dir}" || ! -d "${mod_dir}" ]]; then
    printf 'mod directory is required: %s\n' "${mod_dir}" >&2
    return 1
  fi

  if [[ -d "${mod_dir}/Addons" && ! -d "${mod_dir}/addons" ]]; then
    linux_manager_run_privileged_command mv "${mod_dir}/Addons" "${mod_dir}/addons"
  fi

  if [[ -d "${mod_dir}/Keys" && ! -d "${mod_dir}/keys" ]]; then
    linux_manager_run_privileged_command mv "${mod_dir}/Keys" "${mod_dir}/keys"
  fi

  addons_dir="${mod_dir}/addons"
  keys_dir="${mod_dir}/keys"

  if [[ -d "${addons_dir}" ]]; then
    mapfile -t addon_entries < <(linux_manager_run_privileged_command find "${addons_dir}" -depth)
    for path in "${addon_entries[@]}"; do
      [[ -n "${path}" ]] || continue
      linux_manager_lowercase_deployed_path_basename "${path}" || return 1
    done
  fi

  if [[ -d "${keys_dir}" ]]; then
    mapfile -t key_entries < <(linux_manager_run_privileged_command find "${keys_dir}" -depth)
    for path in "${key_entries[@]}"; do
      [[ -n "${path}" ]] || continue
      linux_manager_lowercase_deployed_path_basename "${path}" || return 1
    done
  fi
}

linux_manager_sync_deployed_mods() {
  local server_root="${1:-}"
  local workshop_root="${2:-}"
  local active_mod_ids_text="${3:-}"
  local tracking_path
  local current_ids=()
  local current_id
  declare -A current_ids_seen=()
  local old_id
  local old_ids=()
  local source_path
  local target_path

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  if [[ -z "${workshop_root}" ]]; then
    workshop_root="$(linux_manager_get_workshop_content_root "${server_root}")" || return 1
  fi

  linux_manager_run_privileged_command mkdir -p "${server_root}"

  tracking_path="$(linux_manager_get_mod_symlink_tracking_path "${server_root}")" || return 1

  while IFS= read -r current_id; do
    current_id="${current_id%$'\r'}"
    [[ -z "${current_id}" ]] && continue

    if ! linux_manager_is_valid_workshop_id "${current_id}"; then
      printf 'unsafe workshop id: %s\n' "${current_id}" >&2
      return 1
    fi

    if [[ -z "${current_ids_seen[$current_id]+x}" ]]; then
      current_ids_seen["$current_id"]=1
      current_ids+=("${current_id}")
    fi
  done <<< "${active_mod_ids_text}"

  if [[ -r "${tracking_path}" ]]; then
    while IFS= read -r old_id; do
      old_id="${old_id%$'\r'}"
      [[ -z "${old_id}" ]] && continue
      old_ids+=("${old_id}")
    done < "${tracking_path}"
  fi

  for current_id in "${current_ids[@]}"; do
    source_path="${workshop_root}/${current_id}"
    target_path="${server_root}/${current_id}"

    if [[ ! -d "${source_path}" ]]; then
      printf 'workshop content folder is missing: %s\n' "${source_path}" >&2
      return 1
    fi

    linux_manager_run_privileged_command rm -rf "${target_path}"
    linux_manager_run_privileged_command cp -a "${source_path}" "${target_path}"
    linux_manager_normalize_deployed_mod_directory "${target_path}" || return 1
  done

  for old_id in "${old_ids[@]}"; do
    if [[ -z "${current_ids_seen[$old_id]+x}" ]]; then
      linux_manager_run_privileged_command rm -rf "${server_root}/${old_id}"
    fi
  done

  linux_manager_write_tracking_file_from_lines "${tracking_path}" "${current_ids[@]}"
}

linux_manager_sync_mod_bikeys() {
  local server_root="${1:-}"
  local active_workshop_ids_text="${2:-}"
  local workshop_root="${3:-}"
  local keys_dir
  local tracking_path
  local current_files=()
  declare -A current_seen=()
  local current_id
  local source_keys_dir
  local bikey_file
  local dest_file
  local old_file
  local old_files=()

  if [[ -z "${server_root}" ]]; then
    printf 'server root is required\n' >&2
    return 1
  fi

  if [[ -z "${workshop_root}" ]]; then
    workshop_root="$(linux_manager_get_workshop_content_root "${server_root}")" || return 1
  fi

  keys_dir="${server_root}/keys"
  mkdir -p "${keys_dir}"

  tracking_path="$(linux_manager_get_mod_bikey_tracking_path "${server_root}")" || return 1

  while IFS= read -r current_id; do
    current_id="${current_id%$'\r'}"
    [[ -z "${current_id}" ]] && continue

    if ! linux_manager_is_valid_workshop_id "${current_id}"; then
      printf 'unsafe workshop id: %s\n' "${current_id}" >&2
      return 1
    fi

    source_keys_dir="${workshop_root}/${current_id}/keys"
    if [[ ! -d "${source_keys_dir}" ]]; then
      continue
    fi

    shopt -s nullglob
    for bikey_file in "${source_keys_dir}"/*.bikey; do
      dest_file="${keys_dir}/$(basename "${bikey_file}")"
      cp -f "${bikey_file}" "${dest_file}"

      local dest_basename
      dest_basename="$(basename "${dest_file}")"
      if [[ -z "${current_seen[$dest_basename]+x}" ]]; then
        current_seen["$dest_basename"]=1
        current_files+=("${dest_basename}")
      fi
    done
    shopt -u nullglob
  done <<< "${active_workshop_ids_text}"

  if [[ -r "${tracking_path}" ]]; then
    while IFS= read -r old_file; do
      old_file="${old_file%$'\r'}"
      [[ -z "${old_file}" ]] && continue
      if ! linux_manager_is_safe_bikey_filename "${old_file}"; then
        printf 'unsafe tracked bikey filename: %s\n' "${old_file}" >&2
        return 1
      fi
      old_files+=("${old_file}")
    done < "${tracking_path}"
  fi

  for old_file in "${old_files[@]}"; do
    if [[ -z "${current_seen[$old_file]+x}" ]]; then
      rm -f "${keys_dir}/${old_file}"
    fi
  done

  linux_manager_write_tracking_file_from_lines "${tracking_path}" "${current_files[@]}"
}

linux_manager_plan_mod_symlink() {
  local server_root="${1:-}"
  local workshop_path="${2:-}"
  local workshop_id="${3:-}"

  if [[ -z "${server_root}" || -z "${workshop_path}" || -z "${workshop_id}" ]]; then
    printf 'server root, workshop path, and workshop id are required\n' >&2
    return 1
  fi

  printf '%s\t%s\n' \
    "${server_root}/${workshop_id}" \
    "${workshop_path}"
}

linux_manager_list_bikey_files() {
  local keys_dir="${1:-}"
  local bikey_files=()

  if [[ -z "${keys_dir}" || ! -d "${keys_dir}" ]]; then
    return 0
  fi

  shopt -s nullglob
  bikey_files=("${keys_dir}"/*.bikey)
  shopt -u nullglob

  if [[ "${#bikey_files[@]}" -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${bikey_files[@]}"
}

linux_manager_default_config_json() {
  local architecture
  architecture="$(linux_manager_detect_architecture)"

  case "${architecture}" in
    x86_64|amd64)
      ;;
    *)
      printf 'unsupported architecture for default config: %s\n' "${architecture}" >&2
      return 1
      ;;
  esac

  printf '%s\n' \
    '{"architecture":"'"${architecture}"'","autostart":true,"modLibrary":{"activeGroup":"","groups":[],"workshopIds":[],"serverWorkshopIds":[]},"profilesPath":"/srv/dayz/server/profiles","serverBranch":"stable","serverRoot":"/srv/dayz/server","serviceName":"dayz-server","steamAccount":{"passwordFile":"/etc/dayz-server-manager/credentials.env","saveMode":"session","username":""},"steamcmdInstallMode":"package","steamcmdPath":"/usr/games/steamcmd"}'
}

linux_manager_initialize_config_file() {
  local config_path="${1:-}"

  if [[ -z "${config_path}" ]]; then
    printf 'config path is required\n' >&2
    return 1
  fi

  if [[ -f "${config_path}" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "${config_path}")"
  linux_manager_default_config_json > "${config_path}"
}

linux_manager_escape_shell_single_quotes() {
  local value="${1:-}"

  value="${value//\'/\'\"\'\"\'}"
  printf "'%s'" "${value}"
}

linux_manager_escape_runscript_value() {
  local value="${1:-}"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

linux_manager_create_secure_temp_file() {
  local target_path="${1:-}"
  local target_dir target_base temp_path

  if [[ -z "${target_path}" ]]; then
    printf 'target path is required\n' >&2
    return 1
  fi

  target_dir="$(dirname "${target_path}")"
  target_base="$(basename "${target_path}")"
  mkdir -p "${target_dir}"

  temp_path="$(
    umask 077
    mktemp "${target_dir}/.${target_base}.XXXXXX"
  )" || return 1
  printf '%s\n' "${temp_path}"
}

linux_manager_create_local_secure_temp_file() {
  local temp_path

  temp_path="$(
    umask 077
    mktemp "${TMPDIR:-/tmp}/dayz-server-manager.XXXXXX"
  )" || return 1
  printf '%s\n' "${temp_path}"
}

linux_manager_effective_uid() {
  printf '%s\n' "${EUID:-$(id -u)}"
}

linux_manager_credentials_path_requires_privileged_access() {
  local credentials_path="${1:-}"
  local effective_uid

  effective_uid="$(linux_manager_effective_uid)"
  if [[ "${effective_uid}" -eq 0 ]]; then
    return 1
  fi

  case "${credentials_path}" in
    /etc/*|/var/*|/root/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

linux_manager_credentials_file_exists() {
  local credentials_path="${1:-}"

  if linux_manager_credentials_path_requires_privileged_access "${credentials_path}"; then
    linux_manager_run_privileged_command test -e "${credentials_path}"
    return $?
  fi

  [[ -e "${credentials_path}" ]]
}

linux_manager_write_steamcmd_runscript() {
  local username="${1:-}"
  local password="${2:-}"
  local runscript_path="${3:-}"
  local temp_path

  if [[ -z "${runscript_path}" ]]; then
    printf 'runscript path is required\n' >&2
    return 1
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${runscript_path}")" || return 1

  if ! {
    printf '+login %s %s\n' \
      "$(linux_manager_escape_runscript_value "${username}")" \
      "$(linux_manager_escape_runscript_value "${password}")"
    printf '+quit\n'
  } > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${runscript_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_save_credentials() {
  local username="${1:-}"
  local password="${2:-}"
  local credentials_path="${3:-}"
  local temp_path

  if [[ -z "${credentials_path}" ]]; then
    printf 'credentials path is required\n' >&2
    return 1
  fi

  if linux_manager_credentials_path_requires_privileged_access "${credentials_path}"; then
    temp_path="$(linux_manager_create_local_secure_temp_file)" || return 1

    if ! {
      printf 'STEAM_USERNAME_B64=%s\n' "$(printf '%s' "${username}" | base64 | tr -d '\n')"
      printf 'STEAM_PASSWORD_B64=%s\n' "$(printf '%s' "${password}" | base64 | tr -d '\n')"
    } > "${temp_path}"; then
      rm -f "${temp_path}"
      return 1
    fi

    linux_manager_run_privileged_command install -d -m 700 "$(dirname "${credentials_path}")" || {
      rm -f "${temp_path}"
      return 1
    }
    linux_manager_run_privileged_command install -m 600 "${temp_path}" "${credentials_path}" || {
      rm -f "${temp_path}"
      return 1
    }
    rm -f "${temp_path}"
    return 0
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${credentials_path}")" || return 1

  if ! {
    printf 'STEAM_USERNAME_B64=%s\n' "$(printf '%s' "${username}" | base64 | tr -d '\n')"
    printf 'STEAM_PASSWORD_B64=%s\n' "$(printf '%s' "${password}" | base64 | tr -d '\n')"
  } > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${credentials_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_decode_base64_value() {
  local encoded_value="${1:-}"

  if [[ -z "${encoded_value}" ]]; then
    return 0
  fi

  if printf '%s' "${encoded_value}" | base64 -d 2>/dev/null; then
    return 0
  fi

  printf '%s' "${encoded_value}" | base64 --decode
}

linux_manager_get_encoded_credential_value_from_file() {
  local credentials_path="${1:-}"
  local key_name="${2:-}"
  local encoded_value=""

  if [[ -z "${credentials_path}" || -z "${key_name}" ]]; then
    printf '%s\n' 'credentials path and key name are required' >&2
    return 1
  fi

  if ! linux_manager_credentials_file_exists "${credentials_path}"; then
    printf 'missing Steam credentials file: %s\n' "${credentials_path}" >&2
    return 1
  fi

  if linux_manager_credentials_path_requires_privileged_access "${credentials_path}"; then
    encoded_value="$(
      linux_manager_run_privileged_command sed -n "s/^${key_name}_B64=\\(.*\\)$/\\1/p" "${credentials_path}" | head -n 1
    )"
  else
    encoded_value="$(
      sed -n "s/^${key_name}_B64=\\(.*\\)$/\\1/p" "${credentials_path}" | head -n 1
    )"
  fi

  if [[ -z "${encoded_value}" ]]; then
    return 0
  fi

  linux_manager_decode_base64_value "${encoded_value}"
}

linux_manager_get_config_json_string_or_default() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local default_value="${2:-}"
  local label="${3:-config value}"
  local sed_expression="${4:-}"
  local value=""

  if [[ ! -e "${config_path}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  if [[ ! -r "${config_path}" ]]; then
    printf 'unreadable config file: %s\n' "${config_path}" >&2
    return 1
  fi

  value="$(sed -n "${sed_expression}" "${config_path}" | head -n 1)"

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  printf '%s\n' "${default_value}"
  return 0
}

linux_manager_escape_sed_replacement() {
  local value="${1:-}"

  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s\n' "${value}"
}

linux_manager_require_jq() {
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi

  printf '%s\n' 'jq is required for Linux config mutation' >&2
  return 1
}

linux_manager_is_safe_linux_absolute_path() {
  local path="${1:-}"

  [[ -n "${path}" ]] || return 1
  [[ "${path}" == /* ]] || return 1

  case "${path}" in
    *$'\n'*|*$'\r'*|*\"*|*\\*|*" "*)
      return 1
      ;;
  esac

  return 0
}

linux_manager_is_safe_service_user() {
  local service_user="${1:-}"

  [[ "${service_user}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "${service_user}" != 'root' ]]
}

linux_manager_normalize_group_name() {
  local group_name="${1:-}"

  group_name="${group_name#"${group_name%%[![:space:]]*}"}"
  group_name="${group_name%"${group_name##*[![:space:]]}"}"

  printf '%s\n' "${group_name}"
}

linux_manager_is_safe_group_name() {
  local group_name
  local group_name_regex='^[A-Za-z0-9._ -]+$'

  group_name="$(linux_manager_normalize_group_name "${1:-}")"

  [[ -n "${group_name}" ]] || return 1

  case "${group_name}" in
    *$'\n'*|*$'\r'*|*\"*|*\\*)
      return 1
      ;;
  esac

  [[ "${group_name}" =~ ${group_name_regex} ]]
}

linux_manager_update_config_with_jq() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local jq_filter="${2:-}"
  local temp_path
  shift 2 || true

  if [[ -z "${jq_filter}" ]]; then
    printf 'jq filter is required\n' >&2
    return 1
  fi

  linux_manager_ensure_config "${config_path}" || return 1
  linux_manager_require_jq || return 1
  temp_path="$(linux_manager_create_secure_temp_file "${config_path}")" || return 1

  if ! MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@" "${jq_filter}" "${config_path}" > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${config_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_get_config_profiles_path() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    '/srv/dayz/server/profiles' \
    'profilesPath' \
    's/.*"profilesPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_update_steam_account_settings() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local username="${2:-}"
  local save_mode="${3:-session}"
  local password_file

  password_file="$(linux_manager_get_config_steam_account_password_file "${config_path}")" || return 1
  linux_manager_update_steam_settings "${config_path}" "${username}" "${save_mode}" "${password_file}"
}

linux_manager_update_server_settings() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local server_branch="${2:-stable}"
  local server_root="${3:-/srv/dayz/server}"
  local profiles_path="${4:-/srv/dayz/server/profiles}"
  local service_name="${5:-dayz-server}"
  local service_user="${6:-dayz}"
  local autostart="${7:-true}"

  case "${server_branch}" in
    stable|experimental)
      ;;
    *)
      printf 'unknown server branch: %s\n' "${server_branch}" >&2
      return 1
      ;;
  esac

  if ! linux_manager_is_safe_linux_absolute_path "${server_root}"; then
    printf 'unsafe server root: %s\n' "${server_root}" >&2
    return 1
  fi

  if ! linux_manager_is_safe_linux_absolute_path "${profiles_path}"; then
    printf 'unsafe profiles path: %s\n' "${profiles_path}" >&2
    return 1
  fi

  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi

  if ! linux_manager_is_safe_service_user "${service_user}"; then
    printf 'unsafe systemd service user: %s\n' "${service_user}" >&2
    return 1
  fi

  case "${autostart}" in
    true|false)
      ;;
    *)
      printf 'invalid autostart value: %s\n' "${autostart}" >&2
      return 1
      ;;
  esac

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.serverBranch = $serverBranch | .serverRoot = $serverRoot | .profilesPath = $profilesPath | .serviceName = $serviceName | .serviceUser = $serviceUser | .autostart = $autostart' \
    --arg serverBranch "${server_branch}" \
    --arg serverRoot "${server_root}" \
    --arg profilesPath "${profiles_path}" \
    --arg serviceName "${service_name}" \
    --arg serviceUser "${service_user}" \
    --argjson autostart "${autostart}"
}

linux_manager_update_steam_settings() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local username="${2:-}"
  local save_mode="${3:-session}"
  local password_file="${4:-/etc/dayz-server-manager/credentials.env}"

  case "${save_mode}" in
    session|saved)
      ;;
    *)
      printf 'invalid Steam save mode: %s\n' "${save_mode}" >&2
      return 1
      ;;
  esac

  case "${username}" in
    *$'\n'*|*$'\r'*|*\"*)
      printf 'unsafe Steam username: %s\n' "${username}" >&2
      return 1
      ;;
  esac

  if ! linux_manager_is_safe_linux_absolute_path "${password_file}"; then
    printf 'unsafe Steam credentials path: %s\n' "${password_file}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.steamAccount = ((.steamAccount // {}) + {username:$username, saveMode:$saveMode, passwordFile:$passwordFile})' \
    --arg username "${username}" \
    --arg saveMode "${save_mode}" \
    --arg passwordFile "${password_file}"
}

linux_manager_unique_workshop_ids_from_text() {
  local ids_text="${1:-}"
  local workshop_id
  local result=()
  declare -A seen=()

  while IFS= read -r workshop_id; do
    workshop_id="${workshop_id%$'\r'}"
    [[ -z "${workshop_id}" ]] && continue

    if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
      printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
      return 1
    fi

    if [[ -z "${seen[$workshop_id]+x}" ]]; then
      seen["$workshop_id"]=1
      result+=("${workshop_id}")
    fi
  done <<< "${ids_text}"

  printf '%s\n' "${result[@]}"
}

linux_manager_workshop_ids_json_from_text() {
  local ids_text="${1:-}"
  local normalized_ids

  linux_manager_require_jq || return 1
  normalized_ids="$(linux_manager_unique_workshop_ids_from_text "${ids_text}")" || return 1
  printf '%s\n' "${normalized_ids}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

linux_manager_add_workshop_id() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.workshopIds = ((.modLibrary.workshopIds // []) + [$workshopId] | unique)' \
    --arg workshopId "${workshop_id}"
}

linux_manager_remove_workshop_id() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.workshopIds = ((.modLibrary.workshopIds // []) | map(select(. != $workshopId)))' \
    --arg workshopId "${workshop_id}"
}

linux_manager_upsert_mod_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"
  local client_ids_text="${3:-}"
  local server_ids_text="${4:-}"
  local client_ids_json
  local server_ids_json

  group_name="$(linux_manager_normalize_group_name "${group_name}")"

  if ! linux_manager_is_safe_group_name "${group_name}"; then
    printf 'unsafe mod group name: %s\n' "${group_name}" >&2
    return 1
  fi

  client_ids_json="$(linux_manager_workshop_ids_json_from_text "${client_ids_text}")" || return 1
  server_ids_json="$(linux_manager_workshop_ids_json_from_text "${server_ids_text}")" || return 1

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.groups = (((.modLibrary.groups // []) | map(select(.name != $groupName))) + [{"name":$groupName,"mods":$mods,"serverMods":$serverMods}])' \
    --arg groupName "${group_name}" \
    --argjson mods "${client_ids_json}" \
    --argjson serverMods "${server_ids_json}"
}

linux_manager_set_active_mod_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"

  group_name="$(linux_manager_normalize_group_name "${group_name}")"

  if [[ -n "${group_name}" ]]; then
    if ! linux_manager_is_safe_group_name "${group_name}"; then
      printf 'unsafe mod group name: %s\n' "${group_name}" >&2
      return 1
    fi

    if ! linux_manager_get_config_mod_library_group_exists "${config_path}" "${group_name}"; then
      printf 'unknown mod group: %s\n' "${group_name}" >&2
      return 1
    fi
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.activeGroup = $groupName' \
    --arg groupName "${group_name}"
}

linux_manager_clear_saved_steam_credentials() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local credentials_path
  local username

  credentials_path="$(linux_manager_get_config_steam_account_password_file "${config_path}")" || return 1
  username="$(linux_manager_get_config_steam_account_username "${config_path}")" || return 1

  if linux_manager_credentials_file_exists "${credentials_path}"; then
    if linux_manager_credentials_path_requires_privileged_access "${credentials_path}"; then
      linux_manager_run_privileged_command rm -f -- "${credentials_path}" || return 1
    else
      rm -f -- "${credentials_path}" || return 1
    fi
  fi
  linux_manager_update_steam_settings "${config_path}" "${username}" 'session' "${credentials_path}"
}

linux_manager_get_config_server_branch() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    'stable' \
    'serverBranch' \
    's/.*"serverBranch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_config_server_root() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    '/srv/dayz/server' \
    'serverRoot' \
    's/.*"serverRoot"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_config_steamcmd_path() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    '/usr/games/steamcmd' \
    'steamcmdPath' \
    's/.*"steamcmdPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_config_service_name() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    'dayz-server' \
    'serviceName' \
    's/.*"serviceName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_config_autostart() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    'true' \
    'autostart' \
    's/.*"autostart"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p'
}

linux_manager_get_config_service_user() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    'dayz' \
    'serviceUser' \
    's/.*"serviceUser"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_config_mod_library_active_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -e "${config_path}" ]]; then
    printf '%s\n' ''
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'jq is required for Linux mod configuration parsing' >&2
    return 1
  fi

  jq -r '.modLibrary.activeGroup // ""' "${config_path}" 2>/dev/null | head -n 1
}

linux_manager_get_config_mod_library_group_exists() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"

  if [[ -z "${group_name}" || ! -r "${config_path}" ]]; then
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'jq is required for Linux mod configuration parsing' >&2
    return 1
  fi

  jq -e --arg group_name "${group_name}" '.modLibrary.groups[]? | select(.name == $group_name) | .name' "${config_path}" >/dev/null 2>&1
}

linux_manager_get_config_mod_library_group_array_values() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"
  local array_name="${3:-}"

  if [[ -z "${group_name}" || -z "${array_name}" || ! -r "${config_path}" ]]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'jq is required for Linux mod configuration parsing' >&2
    return 1
  fi

  jq -r --arg group_name "${group_name}" --arg array_name "${array_name}" '
    .modLibrary.groups[]? |
    select(.name == $group_name) |
    .[$array_name] // [] |
    .[]?
  ' "${config_path}" 2>/dev/null
}

linux_manager_get_config_mod_library_group_mods() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"

  linux_manager_get_config_mod_library_group_array_values "${config_path}" "${group_name}" 'mods'
}

linux_manager_get_config_mod_library_group_server_mods() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"

  linux_manager_get_config_mod_library_group_array_values "${config_path}" "${group_name}" 'serverMods'
}

linux_manager_get_config_mod_library_workshop_ids() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -r "${config_path}" ]]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'jq is required for Linux mod configuration parsing' >&2
    return 1
  fi

  jq -r '.modLibrary.workshopIds // [] | .[]?' "${config_path}" 2>/dev/null
}

linux_manager_get_config_mod_library_server_workshop_ids() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -r "${config_path}" ]]; then
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'jq is required for Linux mod configuration parsing' >&2
    return 1
  fi

  jq -r '.modLibrary.serverWorkshopIds // [] | .[]?' "${config_path}" 2>/dev/null
}

linux_manager_filter_unique_nonempty_lines() {
  local line
  declare -A seen=()

  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "${line}" ]] && continue

    if [[ -z "${seen[$line]+x}" ]]; then
      seen["$line"]=1
      printf '%s\n' "${line}"
    fi
  done
}

linux_manager_get_active_client_mods() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local active_group=""

  active_group="$(linux_manager_get_config_mod_library_active_group "${config_path}")" || return 1

  if [[ -n "${active_group}" ]] && linux_manager_get_config_mod_library_group_exists "${config_path}" "${active_group}"; then
    linux_manager_get_config_mod_library_group_mods "${config_path}" "${active_group}" | linux_manager_filter_unique_nonempty_lines
    return 0
  fi

  linux_manager_get_config_mod_library_workshop_ids "${config_path}" | linux_manager_filter_unique_nonempty_lines
}

linux_manager_get_active_server_mods() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local active_group=""

  active_group="$(linux_manager_get_config_mod_library_active_group "${config_path}")" || return 1

  if [[ -n "${active_group}" ]] && linux_manager_get_config_mod_library_group_exists "${config_path}" "${active_group}"; then
    linux_manager_get_config_mod_library_group_server_mods "${config_path}" "${active_group}" | linux_manager_filter_unique_nonempty_lines
    return 0
  fi

  linux_manager_get_config_mod_library_server_workshop_ids "${config_path}" | linux_manager_filter_unique_nonempty_lines
}

linux_manager_get_active_workshop_ids() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  {
    linux_manager_get_active_client_mods "${config_path}"
    linux_manager_get_active_server_mods "${config_path}"
  } | linux_manager_filter_unique_nonempty_lines
}

linux_manager_build_workshop_download_command() {
  local workshop_id="${1:-}"
  workshop_id="${workshop_id%$'\r'}"

  if [[ -z "${workshop_id}" ]]; then
    printf 'workshop id is required\n' >&2
    return 1
  fi

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  printf 'workshop_download_item %s %s validate\n' "$(linux_manager_get_workshop_app_id)" "${workshop_id}"
}

linux_manager_build_steamcmd_workshop_runscript_content() {
  local server_root="${1:-}"
  local username="${2:-}"
  local password="${3:-}"
  shift 3 || true
  local workshop_id

  if [[ -z "${server_root}" || -z "${username}" || -z "${password}" ]]; then
    printf 'server root, username, and password are required\n' >&2
    return 1
  fi

  printf 'force_install_dir %s\n' "$(linux_manager_escape_runscript_value "${server_root}")"
  printf 'login %s %s\n' \
    "$(linux_manager_escape_runscript_value "${username}")" \
    "$(linux_manager_escape_runscript_value "${password}")"

  while (( "$#" > 0 )); do
    workshop_id="${1:-}"
    shift || true

    if [[ -z "${workshop_id}" ]]; then
      continue
    fi

    linux_manager_build_workshop_download_command "${workshop_id}"
  done

  printf 'quit\n'
}

linux_manager_write_steamcmd_workshop_runscript() {
  local server_root="${1:-}"
  local username="${2:-}"
  local password="${3:-}"
  local runscript_path="${4:-}"
  shift 4 || true
  local temp_path

  if [[ -z "${runscript_path}" ]]; then
    printf 'runscript path is required\n' >&2
    return 1
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${runscript_path}")" || return 1

  if ! linux_manager_build_steamcmd_workshop_runscript_content \
    "${server_root}" \
    "${username}" \
    "${password}" \
    "$@" > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${runscript_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_get_config_steam_account_username() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -r "${config_path}" ]]; then
    printf '%s\n' ''
    return 0
  fi

  linux_manager_require_jq || return 1
  jq -r '.steamAccount.username // ""' "${config_path}" 2>/dev/null | head -n 1
}

linux_manager_get_config_steam_account_password_file() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -r "${config_path}" ]]; then
    printf '%s\n' '/etc/dayz-server-manager/credentials.env'
    return 0
  fi

  linux_manager_require_jq || return 1
  jq -r '.steamAccount.passwordFile // "/etc/dayz-server-manager/credentials.env"' "${config_path}" 2>/dev/null | head -n 1
}

linux_manager_get_config_steam_account_save_mode() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  if [[ ! -r "${config_path}" ]]; then
    printf '%s\n' 'session'
    return 0
  fi

  linux_manager_require_jq || return 1
  jq -r '.steamAccount.saveMode // "session"' "${config_path}" 2>/dev/null | head -n 1
}

linux_manager_get_steam_password_from_file() {
  local password_file="${1:-}"
  local steam_password=""

  if [[ -z "${password_file}" ]]; then
    printf 'password file is required\n' >&2
    return 1
  fi

  steam_password="$(linux_manager_get_encoded_credential_value_from_file "${password_file}" 'STEAM_PASSWORD')" || return 1

  if [[ -z "${steam_password}" ]]; then
    printf 'missing Steam password in credentials file: %s\n' "${password_file}" >&2
    return 1
  fi

  printf '%s\n' "${steam_password}"
}

linux_manager_get_steam_username_from_file() {
  local password_file="${1:-}"
  local steam_username=""

  if [[ -z "${password_file}" ]]; then
    printf 'password file is required\n' >&2
    return 1
  fi

  steam_username="$(linux_manager_get_encoded_credential_value_from_file "${password_file}" 'STEAM_USERNAME')" || return 1

  printf '%s\n' "${steam_username}"
}

linux_manager_is_steamcmd_available() {
  local steamcmd_path="${1:-}"

  [[ -n "${steamcmd_path}" && -x "${steamcmd_path}" ]]
}

linux_manager_get_steamcmd_prereq_commands() {
  printf '%s\n' \
    'sudo dpkg --add-architecture i386' \
    'sudo apt-get update' \
    'sudo apt-get install -y software-properties-common' \
    'sudo add-apt-repository -y multiverse' \
    'sudo apt-get update' \
    'sudo apt-get install -y steamcmd lib32gcc-s1 jq'
}

linux_manager_build_steamcmd_update_runscript_content() {
  local server_root="${1:-}"
  local username="${2:-}"
  local password="${3:-}"
  local server_app_id="${4:-}"

  if [[ -z "${server_root}" || -z "${username}" || -z "${password}" || -z "${server_app_id}" ]]; then
    printf 'server root, username, password, and app id are required\n' >&2
    return 1
  fi

  printf '%s\n' \
    "force_install_dir $(linux_manager_escape_runscript_value "${server_root}")" \
    "login $(linux_manager_escape_runscript_value "${username}") $(linux_manager_escape_runscript_value "${password}")" \
    "app_update ${server_app_id} validate" \
    'quit'
}

linux_manager_write_steamcmd_update_runscript() {
  local server_root="${1:-}"
  local username="${2:-}"
  local password="${3:-}"
  local server_app_id="${4:-}"
  local runscript_path="${5:-}"
  local temp_path

  if [[ -z "${runscript_path}" ]]; then
    printf 'runscript path is required\n' >&2
    return 1
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${runscript_path}")" || return 1

  if ! linux_manager_build_steamcmd_update_runscript_content \
    "${server_root}" \
    "${username}" \
    "${password}" \
    "${server_app_id}" > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${runscript_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_execute_steamcmd_runscript() {
  local steamcmd_path="${1:-}"
  local runscript_path="${2:-}"

  if ! linux_manager_is_steamcmd_available "${steamcmd_path}"; then
    printf 'steamcmd is not available: %s\n' "${steamcmd_path}" >&2
    return 1
  fi

  "${steamcmd_path}" +runscript "${runscript_path}"
}

linux_manager_run_shell_command() {
  local command="${1:-}"

  if [[ -z "${command}" ]]; then
    printf 'command is required\n' >&2
    return 1
  fi

  bash -lc "${command}"
}

linux_manager_run_privileged_command() {
  if [[ "$#" -eq 0 ]]; then
    printf 'command is required\n' >&2
    return 1
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

linux_manager_user_exists() {
  local username="${1:-}"

  [[ -n "${username}" ]] || return 1
  id -u "${username}" >/dev/null 2>&1
}

linux_manager_prepare_service_user() {
  local service_user="${1:-}"

  if ! linux_manager_is_safe_service_user "${service_user}"; then
    printf 'unsafe systemd service user: %s\n' "${service_user}" >&2
    return 1
  fi

  if linux_manager_user_exists "${service_user}"; then
    return 0
  fi

  linux_manager_run_privileged_command \
    useradd \
    --system \
    --create-home \
    --shell /usr/sbin/nologin \
    "${service_user}"
}

linux_manager_prepare_owned_directory() {
  local directory_path="${1:-}"
  local service_user="${2:-}"

  if ! linux_manager_is_safe_linux_absolute_path "${directory_path}"; then
    printf 'unsafe directory path: %s\n' "${directory_path}" >&2
    return 1
  fi

  if ! linux_manager_is_safe_service_user "${service_user}"; then
    printf 'unsafe systemd service user: %s\n' "${service_user}" >&2
    return 1
  fi

  linux_manager_run_privileged_command \
    install \
    -d \
    -o "${service_user}" \
    -g "${service_user}" \
    -m 0755 \
    "${directory_path}"
}

linux_manager_repair_existing_path_ownership() {
  local directory_path="${1:-}"
  local service_user="${2:-}"

  if [[ -z "${directory_path}" || ! -e "${directory_path}" ]]; then
    return 0
  fi

  if ! linux_manager_is_safe_service_user "${service_user}"; then
    printf 'unsafe systemd service user: %s\n' "${service_user}" >&2
    return 1
  fi

  linux_manager_run_privileged_command chown -R "${service_user}:${service_user}" "${directory_path}"
}

linux_manager_ensure_server_binary_executable() {
  local server_root="${1:-}"
  local server_binary_path=""

  if [[ -z "${server_root}" ]]; then
    return 1
  fi

  server_binary_path="${server_root}/DayZServer"
  if [[ ! -e "${server_binary_path}" ]]; then
    return 0
  fi

  linux_manager_run_privileged_command chmod 755 "${server_binary_path}"
}

linux_manager_prepare_environment() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_user
  local server_root
  local profiles_path
  local keys_path
  local missions_path

  linux_manager_ensure_config "${config_path}" || return 1

  service_user="$(linux_manager_get_config_service_user "${config_path}")" || return 1
  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1
  profiles_path="$(linux_manager_get_config_profiles_path "${config_path}")" || return 1
  keys_path="${server_root}/keys"
  missions_path="${server_root}/mpmissions"

  linux_manager_prepare_service_user "${service_user}" || return 1
  linux_manager_prepare_owned_directory "${server_root}" "${service_user}" || return 1
  linux_manager_prepare_owned_directory "${profiles_path}" "${service_user}" || return 1
  linux_manager_prepare_owned_directory "${keys_path}" "${service_user}" || return 1
  linux_manager_repair_existing_path_ownership "${profiles_path}" "${service_user}" || return 1
  linux_manager_repair_existing_path_ownership "${keys_path}" "${service_user}" || return 1
  linux_manager_repair_existing_path_ownership "${missions_path}" "${service_user}" || return 1
  linux_manager_ensure_server_binary_executable "${server_root}" || return 1
}

linux_manager_prompt_with_default() {
  local prompt_label="${1:-Value}"
  local default_value="${2:-}"
  local input_value=""

  printf '%s' "${prompt_label}: " >&2
  if [[ -n "${default_value}" ]]; then
    printf '[%s] ' "${default_value}" >&2
  fi

  read -r input_value
  if [[ -n "${input_value}" ]]; then
    printf '%s\n' "${input_value}"
    return 0
  fi

  printf '%s\n' "${default_value}"
}

linux_manager_normalize_id_list_input() {
  local raw_input="${1:-}"

  printf '%s\n' "${raw_input}" | tr ', ' '\n\n' | sed '/^$/d'
}

linux_manager_print_menu_separator() {
  printf '%s\n' ' -------------------------------------'
}

linux_manager_clear_screen() {
  printf '\033[H\033[2J'
}

linux_manager_print_menu_header() {
  local title="${1:-Menu}"

  linux_manager_clear_screen
  printf '%s\n' "${title}"
  linux_manager_print_menu_separator
}

linux_manager_get_steam_account_status() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local snapshot=""
  local snapshot_parts=()
  local server_root=""
  local autostart=""
  local service_user=""
  local service_name=""
  local username=""
  local save_mode=""
  local password_file=""
  local active_group=""
  local active_group_state=""
  local client_count=""
  local server_count=""
  local dangling_count=""

  snapshot="$(linux_manager_get_main_menu_status_snapshot "${config_path}")" || return 1
  linux_manager_split_tab_fields snapshot_parts "${snapshot}"
  server_root="${snapshot_parts[0]:-}"
  autostart="${snapshot_parts[1]:-}"
  service_user="${snapshot_parts[2]:-}"
  service_name="${snapshot_parts[3]:-}"
  username="${snapshot_parts[4]:-}"
  save_mode="${snapshot_parts[5]:-}"
  password_file="${snapshot_parts[6]:-}"
  active_group="${snapshot_parts[7]:-}"
  active_group_state="${snapshot_parts[8]:-}"
  client_count="${snapshot_parts[9]:-}"
  server_count="${snapshot_parts[10]:-}"
  dangling_count="${snapshot_parts[11]:-}"

  linux_manager_format_steam_account_status_from_values "${username}" "${save_mode}" "${password_file}"
}

linux_manager_get_server_runtime_status() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name="${2:-}"
  local active_state=""

  if [[ -z "${service_name}" ]]; then
    service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  fi
  active_state="$(linux_manager_systemctl_is_active "${service_name}" 2>/dev/null || true)"

  case "${active_state}" in
    active)
      printf '%s\n' 'Running'
      ;;
    inactive|failed|activating|deactivating)
      printf '%s\n' "${active_state}"
      ;;
    *)
      printf '%s\n' 'Not running'
      ;;
  esac
}

linux_manager_get_main_menu_status_snapshot() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_require_jq || return 1

  if [[ ! -r "${config_path}" ]]; then
    printf '%s\n' $'/srv/dayz/server\ttrue\tdayz\tdayz-server\t\tsession\t/etc/dayz-server-manager/credentials.env\t\tnone\t0\t0\t0'
    return 0
  fi

  jq -r '
    (.steamAccount // {}) as $steam
    | (.modLibrary // {}) as $mod
    | def active_group_name: ($mod.activeGroup // "");
    def groups: ($mod.groups // []);
    def active_group_record($group_name): ([groups[]? | select(.name == $group_name)] | first);
    (active_group_name) as $active_group
    | (active_group_record($active_group)) as $group
    | ($group.mods // []) as $client_mods
    | ($group.serverMods // []) as $server_mods
    | ($mod.workshopIds // []) as $workshop_ids
    | ($mod.serverWorkshopIds // []) as $server_workshop_ids
    | (if $active_group == "" then "none" elif $group == null then "missing" else "present" end) as $group_state
    | ([$client_mods[]? | select(($workshop_ids | index(.)) == null)] | length) as $missing_client
    | ([$server_mods[]? | select(($server_workshop_ids | index(.)) == null)] | length) as $missing_server
    | [
        (.serverRoot // "/srv/dayz/server"),
        ((if has("autostart") then .autostart else true end) | tostring),
        (.serviceUser // "dayz"),
        (.serviceName // "dayz-server"),
        ($steam.username // ""),
        ($steam.saveMode // "session"),
        ($steam.passwordFile // "/etc/dayz-server-manager/credentials.env"),
        $active_group,
        $group_state,
        (($client_mods | length) | tostring),
        (($server_mods | length) | tostring),
        (($missing_client + $missing_server) | tostring)
      ]
    | @tsv
  ' "${config_path}" 2>/dev/null
}

linux_manager_format_steam_account_status_from_values() {
  local username="${1:-}"
  local save_mode="${2:-session}"
  local password_file="${3:-/etc/dayz-server-manager/credentials.env}"

  if [[ "${save_mode}" == 'saved' ]] && linux_manager_credentials_file_exists "${password_file}"; then
    if [[ -n "${username}" ]]; then
      printf 'Saved (%s)\n' "${username}"
    else
      printf '%s\n' 'Saved'
    fi
    return 0
  fi

  if [[ -n "${username}" ]]; then
    printf 'Session (%s)\n' "${username}"
  else
    printf '%s\n' 'Not configured'
  fi
}

linux_manager_split_tab_fields() {
  local output_array_name="${1:-}"
  local tab_delimited_text="${2:-}"
  local -n output_array_ref="${output_array_name}"

  output_array_ref=()
  mapfile -td $'\t' output_array_ref < <(printf '%s\t' "${tab_delimited_text}")
}

linux_manager_format_active_group_status_from_values() {
  local active_group="${1:-}"
  local group_state="${2:-none}"
  local client_count="${3:-0}"
  local server_count="${4:-0}"
  local dangling_count="${5:-0}"

  case "${group_state}" in
    none)
      printf '%s\n' '<none>'
      return 0
      ;;
    missing)
      printf '%s\n' "${active_group} (missing)"
      return 0
      ;;
  esac

  printf '%s (%s mods, %s serverMods' "${active_group}" "${client_count}" "${server_count}"
  if [[ "${dangling_count}" -gt 0 ]]; then
    printf ', %s missing references' "${dangling_count}"
  fi
  printf ')\n'
}

linux_manager_get_active_group_status_line() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local snapshot=""
  local snapshot_parts=()
  local server_root=""
  local autostart=""
  local service_user=""
  local service_name=""
  local username=""
  local save_mode=""
  local password_file=""
  local active_group=""
  local group_state=""
  local client_count=""
  local server_count=""
  local dangling_count=""

  snapshot="$(linux_manager_get_main_menu_status_snapshot "${config_path}")" || return 1
  linux_manager_split_tab_fields snapshot_parts "${snapshot}"
  server_root="${snapshot_parts[0]:-}"
  autostart="${snapshot_parts[1]:-}"
  service_user="${snapshot_parts[2]:-}"
  service_name="${snapshot_parts[3]:-}"
  username="${snapshot_parts[4]:-}"
  save_mode="${snapshot_parts[5]:-}"
  password_file="${snapshot_parts[6]:-}"
  active_group="${snapshot_parts[7]:-}"
  group_state="${snapshot_parts[8]:-}"
  client_count="${snapshot_parts[9]:-}"
  server_count="${snapshot_parts[10]:-}"
  dangling_count="${snapshot_parts[11]:-}"

  linux_manager_format_active_group_status_from_values \
    "${active_group}" \
    "${group_state}" \
    "${client_count}" \
    "${server_count}" \
    "${dangling_count}"
}

linux_manager_print_main_menu_status() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local snapshot=""
  local snapshot_parts=()
  local server_status
  local server_root=""
  local autostart=""
  local service_user=""
  local service_name=""
  local steam_username=""
  local steam_save_mode=""
  local steam_password_file=""
  local active_group=""
  local active_group_state=""
  local client_count=""
  local server_count=""
  local dangling_count=""
  local steam_status
  local active_group_status

  snapshot="$(linux_manager_get_main_menu_status_snapshot "${config_path}")" || return 1
  linux_manager_split_tab_fields snapshot_parts "${snapshot}"
  server_root="${snapshot_parts[0]:-}"
  autostart="${snapshot_parts[1]:-}"
  service_user="${snapshot_parts[2]:-}"
  service_name="${snapshot_parts[3]:-}"
  steam_username="${snapshot_parts[4]:-}"
  steam_save_mode="${snapshot_parts[5]:-}"
  steam_password_file="${snapshot_parts[6]:-}"
  active_group="${snapshot_parts[7]:-}"
  active_group_state="${snapshot_parts[8]:-}"
  client_count="${snapshot_parts[9]:-}"
  server_count="${snapshot_parts[10]:-}"
  dangling_count="${snapshot_parts[11]:-}"

  server_status="$(linux_manager_get_server_runtime_status "${config_path}" "${service_name}")" || server_status='Unknown'
  steam_status="$(linux_manager_format_steam_account_status_from_values "${steam_username}" "${steam_save_mode}" "${steam_password_file}")" || steam_status='Unknown'
  active_group_status="$(linux_manager_format_active_group_status_from_values "${active_group}" "${active_group_state}" "${client_count}" "${server_count}" "${dangling_count}")" || active_group_status='<unknown>'

  printf '%s\n' ' Status'
  linux_manager_print_menu_separator
  printf '  Server      : %s\n' "${server_status}"
  printf '  Directory   : %s\n' "${server_root}"
  printf '  Account     : %s\n' "${steam_status}"
  printf '  Active group: %s\n' "${active_group_status}"
  printf '  Service user: %s\n' "${service_user}"
  printf '  Autostart   : %s\n' "${autostart}"
  linux_manager_print_menu_separator
  printf '\n'
}

linux_manager_print_main_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_print_main_menu_status "${config_path}"
  printf '%s\n' ' Main Menu'
  linux_manager_print_menu_separator
  printf '%s\n' ' 1) Update server'
  printf '%s\n' ' 2) Update mods'
  printf '%s\n' ' 3) Start server'
  printf '%s\n' ' 4) Stop server'
  printf '%s\n' ' 5) SteamCMD Account'
  printf '%s\n' ' 6) Manage mod groups'
  printf '%s\n' ' 7) Manage mods'
  printf '%s\n' ' 8) Remove / Uninstall'
  printf '%s\n' ' 9) Linux service tools'
  printf '%s\n' ' 10) Exit'
  linux_manager_print_menu_separator
}

linux_manager_print_steam_account_menu() {
  linux_manager_print_menu_header 'SteamCMD Account'
  printf '%s\n' ' SteamCMD uses this account for DayZ server and mod downloads.'
  printf '%s\n' ' Using this account once does not save your credentials.'
  printf '\n'
  printf '%s\n' ' 1) Use account once'
  printf '%s\n' ' 2) Save account'
  printf '%s\n' ' 3) Clear saved account'
  printf '%s\n' ' 4) Back to Main Menu'
  linux_manager_print_menu_separator
}

linux_manager_print_mods_menu() {
  linux_manager_print_menu_header 'Manage Mods'
  printf '%s\n' ' 1) List client mods'
  printf '%s\n' ' 2) List server mods'
  printf '%s\n' ' 3) Add mod'
  printf '%s\n' ' 4) Remove mod'
  printf '%s\n' ' 5) Move mod between client/server'
  printf '%s\n' ' 6) Sync/update configured mods now'
  printf '%s\n' ' 7) Back to Main Menu'
  linux_manager_print_menu_separator
}

linux_manager_print_mod_groups_menu() {
  linux_manager_print_menu_header 'Manage Mod Groups'
  printf '%s\n' ' 1) New group'
  printf '%s\n' ' 2) Edit group'
  printf '%s\n' ' 3) Rename group'
  printf '%s\n' ' 4) Copy group'
  printf '%s\n' ' 5) Remove group'
  printf '%s\n' ' 6) Set active group'
  printf '%s\n' ' 7) Clear active group'
  printf '%s\n' ' 8) Back to Main Menu'
  linux_manager_print_menu_separator
}

linux_manager_print_linux_service_tools_menu() {
  linux_manager_print_menu_header 'Linux service tools'
  printf '%s\n' ' 1) Apply service config'
  printf '%s\n' ' 2) Service status'
  printf '%s\n' ' 3) Follow logs'
  printf '%s\n' ' 4) Prepare environment'
  printf '%s\n' ' 5) Toggle autostart'
  printf '%s\n' ' 6) Edit Linux service settings'
  printf '%s\n' ' 7) Back to Main Menu'
  linux_manager_print_menu_separator
}

linux_manager_print_remove_uninstall_menu() {
  linux_manager_print_menu_header 'Remove / Uninstall'
  printf '%s\n' ' 1) Clear saved SteamCMD path'
  printf '%s\n' ' 2) Remove downloaded mod data'
  printf '%s\n' ' 3) Uninstall DayZ server'
  printf '%s\n' ' 4) Uninstall SteamCMD'
  printf '%s\n' ' 5) Back to Main Menu'
  linux_manager_print_menu_separator
}

linux_manager_print_mod_summary() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_require_jq || return 1
  jq -r '
    "Active group: \(.modLibrary.activeGroup // "")",
    "Workshop IDs: \((.modLibrary.workshopIds // []) | join(","))",
    "Groups:",
    ((.modLibrary.groups // [])[]? | "  - \(.name): mods=[\((.mods // []) | join(","))] serverMods=[\((.serverMods // []) | join(","))]"))
  ' "${config_path}"
}

linux_manager_get_group_names() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_require_jq || return 1
  jq -r '.modLibrary.groups // [] | .[]?.name // empty' "${config_path}" 2>/dev/null
}

linux_manager_array_contains_value() {
  local array_name="${1:-}"
  local needle="${2:-}"
  local value

  [[ -n "${array_name}" ]] || return 1

  local -n array_ref="${array_name}"
  for value in "${array_ref[@]}"; do
    if [[ "${value}" == "${needle}" ]]; then
      return 0
    fi
  done

  return 1
}

linux_manager_array_append_unique() {
  local array_name="${1:-}"
  local value="${2:-}"

  [[ -n "${array_name}" && -n "${value}" ]] || return 0

  if linux_manager_array_contains_value "${array_name}" "${value}"; then
    return 0
  fi

  local -n array_ref="${array_name}"
  array_ref+=("${value}")
}

linux_manager_array_remove_value() {
  local array_name="${1:-}"
  local needle="${2:-}"
  local filtered=()
  local value

  [[ -n "${array_name}" ]] || return 1

  local -n array_ref="${array_name}"
  for value in "${array_ref[@]}"; do
    if [[ "${value}" != "${needle}" ]]; then
      filtered+=("${value}")
    fi
  done

  array_ref=("${filtered[@]}")
}

linux_manager_join_array_with_comma() {
  local array_name="${1:-}"
  local joined=""
  local value

  [[ -n "${array_name}" ]] || return 1

  local -n array_ref="${array_name}"
  for value in "${array_ref[@]}"; do
    [[ -n "${value}" ]] || continue
    if [[ -n "${joined}" ]]; then
      joined+=","
    fi
    joined+="${value}"
  done

  printf '%s\n' "${joined}"
}

linux_manager_get_group_summary_rows() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_require_jq || return 1
  jq -r '.modLibrary.groups // [] | .[]? | [(.name // ""), ((.mods // []) | length | tostring), ((.serverMods // []) | length | tostring)] | @tsv' "${config_path}" 2>/dev/null
}

linux_manager_select_group_from_list() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local prompt_label="${2:-Select a group}"
  local group_rows=()
  local choice=""
  local choice_index=0
  local group_name=""
  local mod_count=""
  local server_mod_count=""

  mapfile -t group_rows < <(linux_manager_get_group_summary_rows "${config_path}")

  if [[ "${#group_rows[@]}" -eq 0 ]]; then
    printf '%s\n' 'No mod groups are defined.' >&2
    printf '\n' >&2
    return 0
  fi

  printf '\n' >&2
  printf '%s\n' ' Groups:' >&2
  linux_manager_print_menu_separator >&2
  local row_index=1
  local row
  for row in "${group_rows[@]}"; do
    IFS=$'\t' read -r group_name mod_count server_mod_count <<< "${row}"
    printf '  %s) %s (%s mods, %s serverMods)\n' "${row_index}" "${group_name}" "${mod_count}" "${server_mod_count}" >&2
    row_index=$((row_index + 1))
  done
  printf '\n' >&2
  printf '%s (0 to cancel): ' "${prompt_label}" >&2

  if ! read -r choice; then
    return 0
  fi

  if [[ "${choice}" == '0' ]]; then
    return 0
  fi

  if ! [[ "${choice}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' 'Invalid selection.' >&2
    printf '\n' >&2
    return 0
  fi

  choice_index=$((choice - 1))
  if (( choice_index < 0 || choice_index >= ${#group_rows[@]} )); then
    printf '%s\n' 'Invalid selection.' >&2
    printf '\n' >&2
    return 0
  fi

  IFS=$'\t' read -r group_name mod_count server_mod_count <<< "${group_rows[$choice_index]}"
  printf '%s\n' "${group_name}"
}

linux_manager_print_group_selection_entries() {
  local heading="${1:-Mods}"
  local kind_label="${2:-client}"
  local available_array_name="${3:-}"
  local selected_array_name="${4:-}"
  local entry_refs_name="${5:-}"
  local entry_index_name="${6:-}"
  local value

  local -n available_ref="${available_array_name}"
  local -n selected_ref="${selected_array_name}"
  local -n entry_refs_ref="${entry_refs_name}"
  local -n entry_index_ref="${entry_index_name}"

  printf '%s\n' "${heading}" >&2

  for value in "${available_ref[@]}"; do
    local marker='[ ]'
    if linux_manager_array_contains_value "${selected_array_name}" "${value}"; then
      marker='[x]'
    fi
    printf '  %s) %s %s\n' "${entry_index_ref}" "${marker}" "${value}" >&2
    entry_refs_ref+=("${kind_label}:${value}")
    entry_index_ref=$((entry_index_ref + 1))
  done

  for value in "${selected_ref[@]}"; do
    if linux_manager_array_contains_value "${available_array_name}" "${value}"; then
      continue
    fi
    printf '  %s) [x] [dangling] %s\n' "${entry_index_ref}" "${value}" >&2
    entry_refs_ref+=("${kind_label}:${value}")
    entry_index_ref=$((entry_index_ref + 1))
  done

  if [[ "${#available_ref[@]}" -eq 0 && "${#selected_ref[@]}" -eq 0 ]]; then
    printf '%s\n' '  (none)' >&2
  fi

  printf '\n' >&2
}

linux_manager_toggle_group_selection_entry() {
  local ref="${1:-}"
  local client_selected_name="${2:-}"
  local server_selected_name="${3:-}"
  local kind="${ref%%:*}"
  local workshop_id="${ref#*:}"

  local -n client_selected_ref="${client_selected_name}"
  local -n server_selected_ref="${server_selected_name}"

  case "${kind}" in
    client)
      if linux_manager_array_contains_value "${client_selected_name}" "${workshop_id}"; then
        linux_manager_array_remove_value "${client_selected_name}" "${workshop_id}"
      else
        linux_manager_array_append_unique "${client_selected_name}" "${workshop_id}"
        linux_manager_array_remove_value "${server_selected_name}" "${workshop_id}"
      fi
      ;;
    server)
      if linux_manager_array_contains_value "${server_selected_name}" "${workshop_id}"; then
        linux_manager_array_remove_value "${server_selected_name}" "${workshop_id}"
      else
        linux_manager_array_append_unique "${server_selected_name}" "${workshop_id}"
        linux_manager_array_remove_value "${client_selected_name}" "${workshop_id}"
      fi
      ;;
  esac
}

linux_manager_edit_group_selection() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"
  local initial_client_ids_text="${3:-}"
  local initial_server_ids_text="${4:-}"
  local client_library_ids=()
  local server_library_ids=()
  local selected_client_ids=()
  local selected_server_ids=()
  local entry_refs=()
  local row_index
  local selection=""
  local selection_index
  local range_start
  local range_end
  local range_value
  local client_csv=""
  local server_csv=""

  mapfile -t client_library_ids < <(linux_manager_get_config_mod_library_workshop_ids "${config_path}")
  mapfile -t server_library_ids < <(linux_manager_get_config_mod_library_server_workshop_ids "${config_path}")
  mapfile -t selected_client_ids < <(printf '%s\n' "${initial_client_ids_text}" | linux_manager_normalize_id_list_input)
  mapfile -t selected_server_ids < <(printf '%s\n' "${initial_server_ids_text}" | linux_manager_normalize_id_list_input)

  if [[ "${#client_library_ids[@]}" -eq 0 && "${#server_library_ids[@]}" -eq 0 && "${#selected_client_ids[@]}" -eq 0 && "${#selected_server_ids[@]}" -eq 0 ]]; then
    printf '%s\n' 'No configured mods are available. Add mods in Manage mods first.' >&2
    return 1
  fi

  while true; do
    printf '\n' >&2
    printf 'Editing group: %s\n' "${group_name}" >&2
    linux_manager_print_menu_separator >&2
    printf '%s\n' 'Enter a number or range to toggle mods, c to confirm, or q to cancel.' >&2
    printf '\n' >&2

    entry_refs=()
    row_index=1

    linux_manager_print_group_selection_entries \
      'Client mods' \
      'client' \
      client_library_ids \
      selected_client_ids \
      entry_refs \
      row_index

    linux_manager_print_group_selection_entries \
      'Server mods' \
      'server' \
      server_library_ids \
      selected_server_ids \
      entry_refs \
      row_index

    printf '%s' 'Select an option: ' >&2
    if ! read -r selection; then
      return 0
    fi

    case "${selection}" in
      c|C)
        client_csv="$(linux_manager_join_array_with_comma selected_client_ids)"
        server_csv="$(linux_manager_join_array_with_comma selected_server_ids)"
        printf 'SAVED\t%s\t%s\n' "${client_csv}" "${server_csv}"
        return 0
        ;;
      q|Q)
        printf '%s\n' 'CANCELLED'
        return 0
        ;;
    esac

    if [[ "${selection}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      range_start="${BASH_REMATCH[1]}"
      range_end="${BASH_REMATCH[2]}"

      if (( range_start > range_end )); then
        range_value="${range_start}"
        range_start="${range_end}"
        range_end="${range_value}"
      fi

      if (( range_start < 1 || range_end > ${#entry_refs[@]} )); then
        printf 'Invalid selection range: %s\n' "${selection}" >&2
        continue
      fi

      for (( range_value = range_start; range_value <= range_end; range_value++ )); do
        linux_manager_toggle_group_selection_entry "${entry_refs[$((range_value - 1))]}" selected_client_ids selected_server_ids
      done
      continue
    fi

    if ! [[ "${selection}" =~ ^[0-9]+$ ]]; then
      printf 'Unknown group editor choice: %s\n' "${selection}" >&2
      continue
    fi

    selection_index=$((selection - 1))
    if (( selection_index < 0 || selection_index >= ${#entry_refs[@]} )); then
      printf 'Invalid selection: %s\n' "${selection}" >&2
      continue
    fi

    linux_manager_toggle_group_selection_entry "${entry_refs[$selection_index]}" selected_client_ids selected_server_ids
  done
}

linux_manager_rename_mod_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local old_name="${2:-}"
  local new_name="${3:-}"

  old_name="$(linux_manager_normalize_group_name "${old_name}")"
  new_name="$(linux_manager_normalize_group_name "${new_name}")"

  if ! linux_manager_is_safe_group_name "${old_name}" || ! linux_manager_is_safe_group_name "${new_name}"; then
    printf 'unsafe mod group rename: %s -> %s\n' "${old_name}" "${new_name}" >&2
    return 1
  fi

  if ! linux_manager_get_config_mod_library_group_exists "${config_path}" "${old_name}"; then
    printf 'unknown mod group: %s\n' "${old_name}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.groups = ((.modLibrary.groups // []) | map(if .name == $oldName then .name = $newName else . end)) | .modLibrary.activeGroup = (if .modLibrary.activeGroup == $oldName then $newName else .modLibrary.activeGroup end)' \
    --arg oldName "${old_name}" \
    --arg newName "${new_name}"
}

linux_manager_copy_mod_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local source_name="${2:-}"
  local target_name="${3:-}"
  local client_ids
  local server_ids

  source_name="$(linux_manager_normalize_group_name "${source_name}")"
  target_name="$(linux_manager_normalize_group_name "${target_name}")"

  if ! linux_manager_get_config_mod_library_group_exists "${config_path}" "${source_name}"; then
    printf 'unknown mod group: %s\n' "${source_name}" >&2
    return 1
  fi

  client_ids="$(linux_manager_get_config_mod_library_group_mods "${config_path}" "${source_name}")"
  server_ids="$(linux_manager_get_config_mod_library_group_server_mods "${config_path}" "${source_name}")"

  linux_manager_upsert_mod_group "${config_path}" "${target_name}" "${client_ids}" "${server_ids}"
}

linux_manager_remove_mod_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local group_name="${2:-}"

  group_name="$(linux_manager_normalize_group_name "${group_name}")"

  if ! linux_manager_is_safe_group_name "${group_name}"; then
    printf 'unsafe mod group name: %s\n' "${group_name}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.groups = ((.modLibrary.groups // []) | map(select(.name != $groupName))) | .modLibrary.activeGroup = (if .modLibrary.activeGroup == $groupName then "" else .modLibrary.activeGroup end)' \
    --arg groupName "${group_name}"
}

linux_manager_remove_mod_from_configuration() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.modLibrary.workshopIds = ((.modLibrary.workshopIds // []) | map(select(. != $workshopId))) | .modLibrary.serverWorkshopIds = ((.modLibrary.serverWorkshopIds // []) | map(select(. != $workshopId))) | .modLibrary.groups = ((.modLibrary.groups // []) | map(.mods = ((.mods // []) | map(select(. != $workshopId))) | .serverMods = ((.serverMods // []) | map(select(. != $workshopId)))))' \
    --arg workshopId "${workshop_id}"
}

linux_manager_add_mod_to_active_group() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"
  local mod_type="${3:-client}"
  local active_group
  local jq_filter

  mod_type="${mod_type,,}"

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  active_group="$(linux_manager_get_config_mod_library_active_group "${config_path}")" || return 1

  if [[ -z "${active_group}" ]]; then
    case "${mod_type}" in
      client)
        linux_manager_add_workshop_id "${config_path}" "${workshop_id}" || return 1
        ;;
      server)
        linux_manager_update_config_with_jq \
          "${config_path}" \
          '.modLibrary.serverWorkshopIds = ((.modLibrary.serverWorkshopIds // []) + [$workshopId] | unique)' \
          --arg workshopId "${workshop_id}" || return 1
        ;;
      *)
        printf 'unknown mod type: %s\n' "${mod_type}" >&2
        return 1
        ;;
    esac

    printf 'No active mod group is set. Added the mod to the %s workshop library only.\n' "${mod_type}"
    return 0
  fi

  case "${mod_type}" in
    client)
      linux_manager_add_workshop_id "${config_path}" "${workshop_id}" || return 1
      jq_filter='.modLibrary.groups = ((.modLibrary.groups // []) | map(if .name == $groupName then .mods = ((.mods // []) + [$workshopId] | unique) | .serverMods = ((.serverMods // []) | map(select(. != $workshopId))) else . end))'
      ;;
    server)
      linux_manager_update_config_with_jq \
        "${config_path}" \
        '.modLibrary.serverWorkshopIds = ((.modLibrary.serverWorkshopIds // []) + [$workshopId] | unique)' \
        --arg workshopId "${workshop_id}" || return 1
      jq_filter='.modLibrary.groups = ((.modLibrary.groups // []) | map(if .name == $groupName then .serverMods = ((.serverMods // []) + [$workshopId] | unique) | .mods = ((.mods // []) | map(select(. != $workshopId))) else . end))'
      ;;
    *)
      printf 'unknown mod type: %s\n' "${mod_type}" >&2
      return 1
      ;;
  esac

  linux_manager_update_config_with_jq \
    "${config_path}" \
    "${jq_filter}" \
    --arg groupName "${active_group}" \
    --arg workshopId "${workshop_id}"
}

linux_manager_move_mod_between_active_group_lists() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"
  local target_list="${3:-client}"
  local active_group
  local jq_filter

  target_list="${target_list,,}"

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  active_group="$(linux_manager_get_config_mod_library_active_group "${config_path}")" || return 1
  if [[ -z "${active_group}" ]]; then
    printf '%s\n' 'Set an active mod group before moving mods between client and server lists.' >&2
    return 1
  fi

  case "${target_list}" in
    client)
      linux_manager_add_workshop_id "${config_path}" "${workshop_id}" || return 1
      linux_manager_update_config_with_jq \
        "${config_path}" \
        '.modLibrary.serverWorkshopIds = ((.modLibrary.serverWorkshopIds // []) | map(select(. != $workshopId)))' \
        --arg workshopId "${workshop_id}" || return 1
      jq_filter='.modLibrary.groups = ((.modLibrary.groups // []) | map(if .name == $groupName then .mods = ((.mods // []) + [$workshopId] | unique) | .serverMods = ((.serverMods // []) | map(select(. != $workshopId))) else . end))'
      ;;
    server)
      linux_manager_update_config_with_jq \
        "${config_path}" \
        '.modLibrary.serverWorkshopIds = ((.modLibrary.serverWorkshopIds // []) + [$workshopId] | unique) | .modLibrary.workshopIds = ((.modLibrary.workshopIds // []) | map(select(. != $workshopId)))' \
        --arg workshopId "${workshop_id}" || return 1
      jq_filter='.modLibrary.groups = ((.modLibrary.groups // []) | map(if .name == $groupName then .serverMods = ((.serverMods // []) + [$workshopId] | unique) | .mods = ((.mods // []) | map(select(. != $workshopId))) else . end))'
      ;;
    *)
      printf 'unknown target mod list: %s\n' "${target_list}" >&2
      return 1
      ;;
  esac

  linux_manager_update_config_with_jq \
    "${config_path}" \
    "${jq_filter}" \
    --arg groupName "${active_group}" \
    --arg workshopId "${workshop_id}"
}

linux_manager_toggle_autostart() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local current_autostart
  local new_autostart

  current_autostart="$(linux_manager_get_config_autostart "${config_path}")" || return 1
  if [[ "${current_autostart}" == 'true' ]]; then
    new_autostart='false'
  else
    new_autostart='true'
  fi

  linux_manager_update_server_settings \
    "${config_path}" \
    "$(linux_manager_get_config_server_branch "${config_path}")" \
    "$(linux_manager_get_config_server_root "${config_path}")" \
    "$(linux_manager_get_config_profiles_path "${config_path}")" \
    "$(linux_manager_get_config_service_name "${config_path}")" \
    "$(linux_manager_get_config_service_user "${config_path}")" \
    "${new_autostart}" || return 1

  printf 'Autostart set to %s\n' "${new_autostart}"
}

linux_manager_reset_steamcmd_path() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_update_config_with_jq \
    "${config_path}" \
    '.steamcmdInstallMode = "package" | .steamcmdPath = "/usr/games/steamcmd"'
}

linux_manager_confirm_action() {
  local prompt_text="${1:-Are you sure?}"
  local confirmation=""

  printf '%s [y/N]: ' "${prompt_text}" >&2
  read -r confirmation
  [[ "${confirmation}" =~ ^[Yy]$ ]]
}

linux_manager_remove_downloaded_mod_data() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local workshop_id="${2:-}"
  local server_root
  local workshop_root

  if ! linux_manager_is_valid_workshop_id "${workshop_id}"; then
    printf 'unsafe workshop id: %s\n' "${workshop_id}" >&2
    return 1
  fi

  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1
  workshop_root="$(linux_manager_get_workshop_content_root "${server_root}")" || return 1

  linux_manager_run_privileged_command rm -rf -- "${workshop_root}/${workshop_id}"
  linux_manager_run_privileged_command rm -f -- "${server_root}/${workshop_id}"
}

linux_manager_uninstall_server_files() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name
  local server_root

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1

  linux_manager_systemctl_stop "${service_name}" || true
  linux_manager_run_privileged_command rm -rf -- "${server_root}"
}

linux_manager_uninstall_steamcmd() {
  local purge_status=0

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get purge -y steamcmd steamcmd:i386 || purge_status=$?
    if [[ "${purge_status}" -ne 0 ]]; then
      DEBIAN_FRONTEND=noninteractive apt-get purge -y steamcmd || purge_status=$?
    fi
  else
    linux_manager_run_privileged_command env DEBIAN_FRONTEND=noninteractive apt-get purge -y steamcmd steamcmd:i386 || purge_status=$?
    if [[ "${purge_status}" -ne 0 ]]; then
      linux_manager_run_privileged_command env DEBIAN_FRONTEND=noninteractive apt-get purge -y steamcmd || purge_status=$?
    fi
  fi

  return "${purge_status}"
}

linux_manager_configure_server_settings() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local server_branch
  local server_root
  local profiles_path
  local service_name
  local service_user
  local autostart

  linux_manager_ensure_config "${config_path}" || return 1

  server_branch="$(linux_manager_prompt_with_default 'Server branch (stable/experimental)' "$(linux_manager_get_config_server_branch "${config_path}")")" || return 1
  server_root="$(linux_manager_prompt_with_default 'Server root' "$(linux_manager_get_config_server_root "${config_path}")")" || return 1
  profiles_path="$(linux_manager_prompt_with_default 'Profiles path' "$(linux_manager_get_config_profiles_path "${config_path}")")" || return 1
  service_name="$(linux_manager_prompt_with_default 'Service name' "$(linux_manager_get_config_service_name "${config_path}")")" || return 1
  service_user="$(linux_manager_prompt_with_default 'Service user' "$(linux_manager_get_config_service_user "${config_path}")")" || return 1
  autostart="$(linux_manager_prompt_with_default 'Autostart (true/false)' "$(linux_manager_get_config_autostart "${config_path}")")" || return 1

  linux_manager_update_server_settings \
    "${config_path}" \
    "${server_branch}" \
    "${server_root}" \
    "${profiles_path}" \
    "${service_name}" \
    "${service_user}" \
    "${autostart}" || return 1

  printf '%s\n' 'Updated server settings.'
}

linux_manager_configure_steam_settings() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local username
  local save_mode
  local password_file
  local clear_saved_choice

  linux_manager_ensure_config "${config_path}" || return 1

  username="$(linux_manager_prompt_with_default 'Steam username' "$(linux_manager_get_config_steam_account_username "${config_path}")")" || return 1
  save_mode="$(linux_manager_prompt_with_default 'Steam save mode (session/saved)' "$(linux_manager_get_config_steam_account_save_mode "${config_path}")")" || return 1
  password_file="$(linux_manager_prompt_with_default 'Steam credentials path' "$(linux_manager_get_config_steam_account_password_file "${config_path}")")" || return 1

  linux_manager_update_steam_settings "${config_path}" "${username}" "${save_mode}" "${password_file}" || return 1

  printf '%s' 'Clear saved Steam credentials file now? [y/N]: ' >&2
  read -r clear_saved_choice
  if [[ "${clear_saved_choice}" =~ ^[Yy]$ ]]; then
    linux_manager_clear_saved_steam_credentials "${config_path}" || return 1
  fi

  printf '%s\n' 'Updated Steam account settings.'
}

linux_manager_manage_steam_account_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local choice=""
  local username=""
  local password=""
  local password_file=""

  linux_manager_ensure_config "${config_path}" || return 1

  while true; do
    linux_manager_print_steam_account_menu
    printf '%s' 'Select an option: '
    if ! read -r choice; then
      return 0
    fi

    case "${choice}" in
      1)
        username="$(linux_manager_get_config_steam_account_username "${config_path}")" || return 1
        IFS=$'\t' read -r username password <<< "$(linux_manager_prompt_for_steam_credentials "${username}" '')" || return 1
        linux_manager_update_steam_account_settings "${config_path}" "${username}" 'session' || return 1
        printf '%s\n' 'Stored the Steam username for one-time use.'
        ;;
      2)
        username="$(linux_manager_get_config_steam_account_username "${config_path}")" || return 1
        password_file="$(linux_manager_get_config_steam_account_password_file "${config_path}")" || return 1
        IFS=$'\t' read -r username password <<< "$(linux_manager_prompt_for_steam_credentials "${username}" '')" || return 1
        linux_manager_save_credentials "${username}" "${password}" "${password_file}" || return 1
        linux_manager_update_steam_account_settings "${config_path}" "${username}" 'saved' || return 1
        printf '%s\n' 'Saved the SteamCMD account.'
        ;;
      3)
        linux_manager_clear_saved_steam_credentials "${config_path}" || return 1
        printf '%s\n' 'Cleared the saved SteamCMD account.'
        ;;
      4)
        return 0
        ;;
      *)
        printf 'Unknown Steam account menu choice: %s\n' "${choice}" >&2
        ;;
    esac

    printf '\n'
  done
}

linux_manager_list_mods_with_heading() {
  local heading="${1:-Mods}"
  shift || true
  local mod_ids=("$@")
  local mod_id

  printf '%s\n' "${heading}"
  if [[ "${#mod_ids[@]}" -eq 0 ]]; then
    printf '%s\n' '(none)'
    return 0
  fi

  for mod_id in "${mod_ids[@]}"; do
    printf ' - %s\n' "${mod_id}"
  done
}

linux_manager_manage_mods_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local choice=""
  local workshop_id=""
  local mod_type=""
  local active_group=""
  local client_mods=()
  local server_mods=()

  linux_manager_ensure_config "${config_path}" || return 1

  while true; do
    linux_manager_print_mods_menu
    printf '%s' 'Select an option: '
    if ! read -r choice; then
      return 0
    fi

    case "${choice}" in
      1)
        mapfile -t client_mods < <(linux_manager_get_active_client_mods "${config_path}")
        linux_manager_list_mods_with_heading 'Client mods' "${client_mods[@]}"
        ;;
      2)
        mapfile -t server_mods < <(linux_manager_get_active_server_mods "${config_path}")
        linux_manager_list_mods_with_heading 'Server mods' "${server_mods[@]}"
        ;;
      3)
        workshop_id="$(linux_manager_prompt_with_default 'Workshop ID to add' '')" || return 1
        mod_type="$(linux_manager_prompt_with_default 'Mod type (client/server)' 'client')" || return 1
        linux_manager_add_mod_to_active_group "${config_path}" "${workshop_id}" "${mod_type}" || return 1
        printf '%s\n' 'Added mod to configuration.'
        ;;
      4)
        workshop_id="$(linux_manager_prompt_with_default 'Workshop ID to remove' '')" || return 1
        linux_manager_remove_mod_from_configuration "${config_path}" "${workshop_id}" || return 1
        printf '%s\n' 'Removed mod from configuration.'
        ;;
      5)
        active_group="$(linux_manager_get_config_mod_library_active_group "${config_path}")" || return 1
        if [[ -z "${active_group}" ]]; then
          printf '%s\n' 'Set an active mod group before moving mods between client and server lists.' >&2
          return 1
        fi
        workshop_id="$(linux_manager_prompt_with_default 'Workshop ID to move' '')" || return 1
        mod_type="$(linux_manager_prompt_with_default 'Move to (client/server)' 'server')" || return 1
        linux_manager_move_mod_between_active_group_lists "${config_path}" "${workshop_id}" "${mod_type}" || return 1
        printf 'Moved mod within active group: %s\n' "${active_group}"
        ;;
      6)
        linux_manager_update_mods "${config_path}" || return 1
        ;;
      7)
        return 0
        ;;
      *)
        printf 'Unknown manage mods choice: %s\n' "${choice}" >&2
        ;;
    esac

    printf '\n'
  done
}

linux_manager_manage_mod_groups_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local choice=""
  local group_name=""
  local new_group_name=""
  local client_mods=""
  local server_mods=""
  local edit_result=""
  local edit_status=""

  linux_manager_ensure_config "${config_path}" || return 1

  while true; do
    linux_manager_print_mod_groups_menu
    printf '%s' 'Select an option: '
    if ! read -r choice; then
      return 0
    fi

    case "${choice}" in
      1)
        group_name="$(linux_manager_prompt_with_default 'New group name' '')" || return 1
        edit_result="$(linux_manager_edit_group_selection "${config_path}" "${group_name}" '' '')" || return 1
        IFS=$'\t' read -r edit_status client_mods server_mods <<< "${edit_result}"
        if [[ "${edit_status}" != 'SAVED' ]]; then
          printf '%s\n' 'Cancelled - group not created.'
          printf '\n'
          continue
        fi
        linux_manager_upsert_mod_group \
          "${config_path}" \
          "${group_name}" \
          "$(linux_manager_normalize_id_list_input "${client_mods}")" \
          "$(linux_manager_normalize_id_list_input "${server_mods}")" || return 1
        printf 'Created group: %s\n' "${group_name}"
        ;;
      2)
        group_name="$(linux_manager_select_group_from_list "${config_path}" 'Select a group to edit')"
        if [[ -z "${group_name}" ]]; then
          continue
        fi
        edit_result="$(linux_manager_edit_group_selection \
          "${config_path}" \
          "${group_name}" \
          "$(linux_manager_get_config_mod_library_group_mods "${config_path}" "${group_name}")" \
          "$(linux_manager_get_config_mod_library_group_server_mods "${config_path}" "${group_name}")")" || return 1
        IFS=$'\t' read -r edit_status client_mods server_mods <<< "${edit_result}"
        if [[ "${edit_status}" != 'SAVED' ]]; then
          printf '%s\n' 'Cancelled - no changes saved.'
          printf '\n'
          continue
        fi
        linux_manager_upsert_mod_group \
          "${config_path}" \
          "${group_name}" \
          "$(linux_manager_normalize_id_list_input "${client_mods}")" \
          "$(linux_manager_normalize_id_list_input "${server_mods}")" || return 1
        printf 'Updated group: %s\n' "${group_name}"
        ;;
      3)
        group_name="$(linux_manager_select_group_from_list "${config_path}" 'Select a group to rename')"
        if [[ -z "${group_name}" ]]; then
          continue
        fi
        new_group_name="$(linux_manager_prompt_with_default 'New group name' '')" || return 1
        linux_manager_rename_mod_group "${config_path}" "${group_name}" "${new_group_name}" || return 1
        printf 'Renamed group: %s -> %s\n' "${group_name}" "${new_group_name}"
        ;;
      4)
        group_name="$(linux_manager_select_group_from_list "${config_path}" 'Select a group to copy')"
        if [[ -z "${group_name}" ]]; then
          continue
        fi
        new_group_name="$(linux_manager_prompt_with_default 'Copied group name' '')" || return 1
        edit_result="$(linux_manager_edit_group_selection \
          "${config_path}" \
          "${new_group_name}" \
          "$(linux_manager_get_config_mod_library_group_mods "${config_path}" "${group_name}")" \
          "$(linux_manager_get_config_mod_library_group_server_mods "${config_path}" "${group_name}")")" || return 1
        IFS=$'\t' read -r edit_status client_mods server_mods <<< "${edit_result}"
        if [[ "${edit_status}" != 'SAVED' ]]; then
          printf '%s\n' 'Cancelled - clone not created.'
          printf '\n'
          continue
        fi
        linux_manager_upsert_mod_group \
          "${config_path}" \
          "${new_group_name}" \
          "$(linux_manager_normalize_id_list_input "${client_mods}")" \
          "$(linux_manager_normalize_id_list_input "${server_mods}")" || return 1
        printf 'Copied group: %s -> %s\n' "${group_name}" "${new_group_name}"
        ;;
      5)
        group_name="$(linux_manager_select_group_from_list "${config_path}" 'Select a group to remove')"
        if [[ -z "${group_name}" ]]; then
          continue
        fi
        if linux_manager_confirm_action "Remove group ${group_name}?"; then
          linux_manager_remove_mod_group "${config_path}" "${group_name}" || return 1
          printf 'Removed group: %s\n' "${group_name}"
        fi
        ;;
      6)
        group_name="$(linux_manager_select_group_from_list "${config_path}" 'Select an active group')"
        if [[ -z "${group_name}" ]]; then
          continue
        fi
        linux_manager_set_active_mod_group "${config_path}" "${group_name}" || return 1
        printf 'Updated active mod group: %s\n' "${group_name}"
        ;;
      7)
        linux_manager_set_active_mod_group "${config_path}" '' || return 1
        printf '%s\n' 'Cleared active mod group.'
        ;;
      8)
        return 0
        ;;
      *)
        printf 'Unknown manage mod groups choice: %s\n' "${choice}" >&2
        ;;
    esac

    printf '\n'
  done
}

linux_manager_manage_linux_service_tools_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local choice=""

  linux_manager_ensure_config "${config_path}" || return 1

  while true; do
    linux_manager_print_linux_service_tools_menu
    printf '%s' 'Select an option: '
    if ! read -r choice; then
      return 0
    fi

    case "${choice}" in
      1)
        linux_manager_apply_service_configuration "${config_path}" || return 1
        printf '%s\n' 'Applied service configuration.'
        ;;
      2)
        linux_manager_service_status "${config_path}" || return 1
        ;;
      3)
        linux_manager_follow_server_logs "${config_path}" || return 1
        ;;
      4)
        linux_manager_prepare_environment "${config_path}" || return 1
        printf '%s\n' 'Prepared the Linux server environment.'
        ;;
      5)
        linux_manager_toggle_autostart "${config_path}" || return 1
        ;;
      6)
        linux_manager_configure_server_settings "${config_path}" || return 1
        ;;
      7)
        return 0
        ;;
      *)
        printf 'Unknown Linux service tools choice: %s\n' "${choice}" >&2
        ;;
    esac

    printf '\n'
  done
}

linux_manager_remove_uninstall_menu() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local choice=""
  local workshop_id=""

  linux_manager_ensure_config "${config_path}" || return 1

  while true; do
    linux_manager_print_remove_uninstall_menu
    printf '%s' 'Select an option: '
    if ! read -r choice; then
      return 0
    fi

    case "${choice}" in
      1)
        linux_manager_reset_steamcmd_path "${config_path}" || return 1
        printf '%s\n' 'Cleared the saved SteamCMD path.'
        ;;
      2)
        workshop_id="$(linux_manager_prompt_with_default 'Workshop ID to remove from disk' '')" || return 1
        if linux_manager_confirm_action "Remove downloaded data for ${workshop_id}?"; then
          linux_manager_remove_downloaded_mod_data "${config_path}" "${workshop_id}" || return 1
          printf 'Removed downloaded mod data: %s\n' "${workshop_id}"
        fi
        ;;
      3)
        if linux_manager_confirm_action 'Uninstall DayZ server files?'; then
          linux_manager_uninstall_server_files "${config_path}" || return 1
          printf '%s\n' 'Removed the DayZ server files.'
        fi
        ;;
      4)
        if linux_manager_confirm_action 'Uninstall SteamCMD?'; then
          linux_manager_uninstall_steamcmd || return 1
          printf '%s\n' 'Removed SteamCMD.'
        fi
        ;;
      5)
        return 0
        ;;
      *)
        printf 'Unknown remove/uninstall choice: %s\n' "${choice}" >&2
        ;;
    esac

    printf '\n'
  done
}

linux_manager_prompt_for_steam_credentials() {
  local default_username="${1:-}"
  local credentials_path="${2:-}"
  local username="${default_username}"
  local username_input=""
  local password=""
  local save_choice=""

  printf '%s' 'Steam username: ' >&2
  if [[ -n "${default_username}" ]]; then
    printf '[%s] ' "${default_username}" >&2
  fi
  read -r username_input
  if [[ -n "${username_input}" ]]; then
    username="${username_input}"
  fi

  printf '%s' 'Steam password: ' >&2
  read -rs password
  printf '\n' >&2

  if [[ -z "${username}" || -z "${password}" ]]; then
    printf '%s\n' 'Steam username and password are required' >&2
    return 1
  fi

  if [[ -n "${credentials_path}" ]]; then
    printf '%s' 'Save credentials for future use? [y/N]: ' >&2
    read -r save_choice
    if [[ "${save_choice}" =~ ^[Yy]$ ]]; then
      linux_manager_save_credentials "${username}" "${password}" "${credentials_path}" || return 1
    fi
  fi

  printf '%s\t%s\n' "${username}" "${password}"
}

linux_manager_ensure_steamcmd_available_or_install() {
  local steamcmd_path="${1:-}"
  local prereq_commands
  local prereq_command

  if linux_manager_is_steamcmd_available "${steamcmd_path}"; then
    return 0
  fi

  prereq_commands="$(linux_manager_get_steamcmd_prereq_commands)" || return 1

  while IFS= read -r prereq_command; do
    [[ -z "${prereq_command}" ]] && continue
    linux_manager_run_shell_command "${prereq_command}" || return 1
  done <<< "${prereq_commands}"

  if ! linux_manager_is_steamcmd_available "${steamcmd_path}"; then
    printf 'steamcmd is still unavailable at %s after prerequisite commands\n' "${steamcmd_path}" >&2
    return 1
  fi
}

linux_manager_resolve_steam_credentials() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local steam_username
  local steam_save_mode
  local steam_password_file
  local steam_password=""
  local credentials=""
  local password_file_exists_before=0
  local resolved_save_mode='session'
  local prompt_credentials_path=""

  steam_username="$(linux_manager_get_config_steam_account_username "${config_path}")" || return 1
  steam_save_mode="$(linux_manager_get_config_steam_account_save_mode "${config_path}")" || return 1
  steam_password_file="$(linux_manager_get_config_steam_account_password_file "${config_path}")" || return 1

  if linux_manager_credentials_file_exists "${steam_password_file}"; then
    password_file_exists_before=1
  fi

  if [[ "${steam_save_mode}" == 'saved' ]] && linux_manager_credentials_file_exists "${steam_password_file}"; then
    steam_password="$(linux_manager_get_steam_password_from_file "${steam_password_file}")" || return 1
    if [[ -z "${steam_username}" ]]; then
      steam_username="$(linux_manager_get_steam_username_from_file "${steam_password_file}")" || return 1
    fi
    resolved_save_mode='saved'
  else
    if [[ "${steam_save_mode}" == 'saved' ]]; then
      prompt_credentials_path="${steam_password_file}"
    fi

    credentials="$(linux_manager_prompt_for_steam_credentials "${steam_username}" "${prompt_credentials_path}")" || return 1
    IFS=$'\t' read -r steam_username steam_password <<< "${credentials}"
    if [[ "${steam_save_mode}" == 'saved' && "${password_file_exists_before}" -eq 0 ]] && linux_manager_credentials_file_exists "${steam_password_file}"; then
      resolved_save_mode='saved'
    fi
  fi

  if [[ -z "${steam_username}" ]]; then
    printf 'missing Steam username in config or credentials file: %s\n' "${steam_password_file}" >&2
    return 1
  fi

  linux_manager_update_steam_account_settings "${config_path}" "${steam_username}" "${resolved_save_mode}" || return 1
  printf '%s\t%s\n' "${steam_username}" "${steam_password}"
}

linux_manager_get_template_path() {
  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/dayz-server.service.template"
}

linux_manager_render_service_file() {
  local server_root="${1:-}"
  local service_user="${2:-}"
  local launch_args="${3:-}"
  local output_path="${4:-}"
  local template_path template_content temp_path working_directory exec_start

  if [[ -z "${server_root}" || -z "${service_user}" || -z "${output_path}" ]]; then
    printf 'server root, service user, and output path are required\n' >&2
    return 1
  fi

  if [[ "${service_user}" =~ [^A-Za-z0-9._-] ]]; then
    printf 'unsafe systemd service user: %s\n' "${service_user}" >&2
    return 1
  fi

  if [[ "${service_user}" == 'root' ]]; then
    printf 'refusing to run DayZ server as root\n' >&2
    return 1
  fi

  case "${server_root}" in
    *$'\n'*|*$'\r'*|*\"*|*\\*|*" "*)
      printf 'unsafe systemd server root: %s\n' "${server_root}" >&2
      return 1
      ;;
  esac

  case "${launch_args}" in
    *$'\n'*|*$'\r'*)
      printf 'unsafe systemd launch args: %s\n' "${launch_args}" >&2
      return 1
      ;;
  esac

  template_path="$(linux_manager_get_template_path)"
  if [[ ! -f "${template_path}" ]]; then
    printf 'service template not found: %s\n' "${template_path}" >&2
    return 1
  fi

  template_content="$(< "${template_path}")"
  working_directory="${server_root}"
  exec_start="${server_root}/DayZServer"
  if [[ -n "${launch_args}" ]]; then
    exec_start+=" ${launch_args}"
  fi

  temp_path="$(linux_manager_create_secure_temp_file "${output_path}")" || return 1

  template_content="${template_content//'{{SERVER_ROOT}}'/${working_directory}}"
  template_content="${template_content//'{{SERVICE_USER}}'/${service_user}}"
  template_content="${template_content//'{{EXEC_START}}'/${exec_start}}"

  if ! printf '%s\n' "${template_content}" > "${temp_path}"; then
    rm -f "${temp_path}"
    return 1
  fi

  if ! mv -f "${temp_path}" "${output_path}"; then
    rm -f "${temp_path}"
    return 1
  fi
}

linux_manager_systemctl_start() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl start "${service_name}"
}

linux_manager_systemctl_stop() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl stop "${service_name}"
}

linux_manager_systemctl_restart() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl restart "${service_name}"
}

linux_manager_systemctl_status() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl status "${service_name}"
}

linux_manager_systemctl_reset_failed() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl reset-failed "${service_name}"
}

linux_manager_systemctl_disable() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl disable "${service_name}"
}

linux_manager_systemctl_enable() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl enable "${service_name}"
}

linux_manager_systemctl_daemon_reload() {
  linux_manager_run_privileged_command systemctl daemon-reload
}

linux_manager_journalctl_follow() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command journalctl -u "${service_name}" -n 100 -f
}

linux_manager_systemctl_is_active() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl is-active "${service_name}"
}

linux_manager_systemctl_is_enabled() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl is-enabled "${service_name}"
}

linux_manager_systemctl_show_main_pid() {
  local service_name="${1:-dayz-server}"

  linux_manager_run_privileged_command systemctl show "${service_name}" --property MainPID --value
}

linux_manager_journalctl_recent() {
  local service_name="${1:-dayz-server}"
  local line_count="${2:-20}"

  linux_manager_run_privileged_command journalctl -u "${service_name}" -n "${line_count}" --no-pager
}

linux_manager_is_safe_systemd_service_name() {
  local service_name="${1:-}"

  [[ -n "${service_name}" && "${service_name}" =~ ^[A-Za-z0-9._-]+$ ]]
}

linux_manager_get_service_unit_path() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1

  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi

  printf '%s\n' "/etc/systemd/system/${service_name}.service"
}

linux_manager_render_service_file_from_config() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local output_path="${2:-}"
  local server_root
  local service_user
  local launch_args

  if [[ -z "${output_path}" ]]; then
    printf 'output path is required\n' >&2
    return 1
  fi

  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1
  service_user="$(linux_manager_get_config_service_user "${config_path}")" || return 1
  launch_args="$(linux_manager_build_config_driven_launch_args "${config_path}")" || return 1

  linux_manager_render_service_file \
    "${server_root}" \
    "${service_user}" \
    "${launch_args}" \
    "${output_path}"
}

linux_manager_install_or_update_systemd_unit_from_config() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local unit_path="${2:-}"

  linux_manager_ensure_config "${config_path}" || return 1
  linux_manager_prepare_environment "${config_path}" || return 1

  if [[ -z "${unit_path}" ]]; then
    unit_path="$(linux_manager_get_service_unit_path "${config_path}")" || return 1
  fi

  linux_manager_render_service_file_from_config "${config_path}" "${unit_path}" || return 1
  linux_manager_systemctl_daemon_reload || return 1
}

linux_manager_apply_service_configuration() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name
  local autostart

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  autostart="$(linux_manager_get_config_autostart "${config_path}")" || return 1

  linux_manager_install_or_update_systemd_unit_from_config "${config_path}" || return 1

  if [[ "${autostart}" == 'true' ]]; then
    linux_manager_systemctl_enable "${service_name}"
  else
    linux_manager_systemctl_disable "${service_name}"
  fi
}

linux_manager_start_server() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  linux_manager_apply_service_configuration "${config_path}" || return 1
  linux_manager_systemctl_start "${service_name}"
}

linux_manager_stop_server() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi
  linux_manager_systemctl_stop "${service_name}" || return 1
  linux_manager_systemctl_reset_failed "${service_name}"
}

linux_manager_restart_server() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  linux_manager_apply_service_configuration "${config_path}" || return 1
  linux_manager_systemctl_restart "${service_name}"
}

linux_manager_service_status() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name
  local active_state
  local enabled_state
  local main_pid
  local recent_logs

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi

  active_state="$(linux_manager_systemctl_is_active "${service_name}" 2>/dev/null || true)"
  enabled_state="$(linux_manager_systemctl_is_enabled "${service_name}" 2>/dev/null || true)"
  main_pid="$(linux_manager_systemctl_show_main_pid "${service_name}" 2>/dev/null || true)"
  recent_logs="$(linux_manager_journalctl_recent "${service_name}" 20 2>/dev/null || true)"

  [[ -n "${active_state}" ]] || active_state='unknown'
  [[ -n "${enabled_state}" ]] || enabled_state='unknown'
  [[ -n "${main_pid}" ]] || main_pid='unknown'

  printf 'Service: %s\n' "${service_name}"
  printf 'Active: %s\n' "${active_state}"
  printf 'Enabled: %s\n' "${enabled_state}"
  printf 'Main PID: %s\n' "${main_pid}"
  printf '%s\n' 'Recent logs:'
  if [[ -n "${recent_logs}" ]]; then
    printf '%s\n' "${recent_logs}"
  else
    printf '%s\n' '(none)'
  fi
}

linux_manager_follow_server_logs() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name

  service_name="$(linux_manager_get_config_service_name "${config_path}")" || return 1
  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi
  linux_manager_journalctl_follow "${service_name}"
}

linux_manager_update_server() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local server_branch
  local server_root
  local steamcmd_path
  local credentials
  local steam_username
  local steam_password
  local runscript_path

  linux_manager_ensure_config "${config_path}"
  linux_manager_prepare_environment "${config_path}" || return 1

  server_branch="$(linux_manager_get_config_server_branch "${config_path}")" || return 1
  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1
  steamcmd_path="$(linux_manager_get_config_steamcmd_path "${config_path}")" || return 1
  linux_manager_ensure_steamcmd_available_or_install "${steamcmd_path}" || return 1
  credentials="$(linux_manager_resolve_steam_credentials "${config_path}")" || return 1
  IFS=$'\t' read -r steam_username steam_password <<< "${credentials}"

  runscript_path="$(mktemp "${TMPDIR:-/tmp}/dayz-server-update.XXXXXX")" || return 1

  if ! linux_manager_write_steamcmd_update_runscript \
    "${server_root}" \
    "${steam_username}" \
    "${steam_password}" \
    "$(linux_manager_get_server_app_id "${server_branch}")" \
    "${runscript_path}"; then
    rm -f "${runscript_path}"
    return 1
  fi

  linux_manager_execute_steamcmd_runscript "${steamcmd_path}" "${runscript_path}"
  local execute_status=$?
  if [[ "${execute_status}" -ne 0 ]]; then
    rm -f "${runscript_path}"
    return "${execute_status}"
  fi

  rm -f "${runscript_path}"
  printf 'Server update completed for branch: %s\n' "${server_branch}"
}

linux_manager_update_mods() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local server_root
  local service_user
  local steamcmd_path
  local credentials
  local steam_username
  local steam_password
  local runscript_path
  local active_workshop_ids=()
  local workshop_root

  linux_manager_ensure_config "${config_path}"
  linux_manager_prepare_environment "${config_path}" || return 1

  server_root="$(linux_manager_get_config_server_root "${config_path}")" || return 1
  service_user="$(linux_manager_get_config_service_user "${config_path}")" || return 1
  steamcmd_path="$(linux_manager_get_config_steamcmd_path "${config_path}")" || return 1

  mapfile -t active_workshop_ids < <(linux_manager_get_active_workshop_ids "${config_path}")
  workshop_root="$(linux_manager_get_workshop_content_root "${server_root}")" || return 1

  if [[ "${#active_workshop_ids[@]}" -gt 0 ]]; then
    linux_manager_ensure_steamcmd_available_or_install "${steamcmd_path}" || return 1
    credentials="$(linux_manager_resolve_steam_credentials "${config_path}")" || return 1
    IFS=$'\t' read -r steam_username steam_password <<< "${credentials}"
    runscript_path="$(mktemp "${TMPDIR:-/tmp}/dayz-mods-update.XXXXXX")" || return 1

    if ! linux_manager_write_steamcmd_workshop_runscript \
      "${server_root}" \
      "${steam_username}" \
      "${steam_password}" \
      "${runscript_path}" \
      "${active_workshop_ids[@]}"; then
      rm -f "${runscript_path}"
      return 1
    fi

    linux_manager_execute_steamcmd_runscript "${steamcmd_path}" "${runscript_path}"
    local execute_status=$?
    if [[ "${execute_status}" -ne 0 ]]; then
      rm -f "${runscript_path}"
      return "${execute_status}"
    fi

    rm -f "${runscript_path}"
  fi

  linux_manager_sync_deployed_mods "${server_root}" "${workshop_root}" "$(printf '%s\n' "${active_workshop_ids[@]}")" || return 1
  linux_manager_sync_mod_bikeys "${server_root}" "$(printf '%s\n' "${active_workshop_ids[@]}")" "${workshop_root}" || return 1
  linux_manager_repair_existing_path_ownership "${server_root}/keys" "${service_user}" || return 1
  local workshop_id
  for workshop_id in "${active_workshop_ids[@]}"; do
    linux_manager_repair_existing_path_ownership "${server_root}/${workshop_id}" "${service_user}" || return 1
  done

  printf 'Generated launch args: %s\n' "$(linux_manager_build_config_driven_launch_args "${config_path}")"
  printf 'Mod update completed for %s active workshop item(s)\n' "${#active_workshop_ids[@]}"
}

linux_manager_get_config_server_root() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_get_config_json_string_or_default \
    "${config_path}" \
    '/srv/dayz/server' \
    'serverRoot' \
    's/.*"serverRoot"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

linux_manager_get_cleanup_server_root() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local server_root=""

  if [[ ! -e "${config_path}" ]]; then
    printf 'missing config file: %s\n' "${config_path}" >&2
    return 1
  fi

  if ! server_root="$(linux_manager_get_config_server_root "${config_path}")"; then
    return 1
  fi

  printf '%s\n' "${server_root}"
}

linux_manager_is_safe_absolute_cleanup_path() {
  local path="${1:-}"
  local path_part
  local path_parts

  if [[ -z "${path}" || "${path}" != /* ]]; then
    return 1
  fi

  case "${path}" in
    */|*'//'|*'/./'*|*'/../'*|*/.|*/..)
      return 1
      ;;
  esac

  IFS='/' read -r -a path_parts <<< "${path}"
  for path_part in "${path_parts[@]}"; do
    case "${path_part}" in
      '')
        continue
        ;;
      .|..)
        return 1
        ;;
    esac
  done

  return 0
}

linux_manager_get_uninstall_cleanup_paths() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local config_dir
  local server_root

  config_dir="$(dirname "${config_path}")"
  if ! server_root="$(linux_manager_get_cleanup_server_root "${config_path}")"; then
    return 1
  fi
  if ! linux_manager_is_safe_absolute_cleanup_path "${server_root}"; then
    printf 'unsafe serverRoot for cleanup: %s\n' "${server_root}" >&2
    return 1
  fi
  printf '%s\n' \
    "${config_dir}" \
    '/etc/dayz-server-manager' \
    '/var/lib/dayz-server-manager' \
    '/var/log/dayz-server-manager' \
    "${server_root}"
}

linux_manager_is_manager_owned_cleanup_path() {
  local path="${1:-}"
  local config_path="${2:-$(linux_manager_get_config_path)}"
  local config_dir
  local server_root

  if [[ -z "${path}" || "${path}" == "/" ]]; then
    return 1
  fi

  config_dir="$(dirname "${config_path}")"
  if ! server_root="$(linux_manager_get_cleanup_server_root "${config_path}")"; then
    return 1
  fi
  if ! linux_manager_is_safe_absolute_cleanup_path "${server_root}"; then
    return 1
  fi

  case "${path}" in
    "${config_dir}"|'/etc/dayz-server-manager'|'/var/lib/dayz-server-manager'|'/var/log/dayz-server-manager'|"${server_root}")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

linux_manager_uninstall() {
  local config_path="${1:-$(linux_manager_get_config_path)}"
  local service_name="${2:-dayz-server}"
  local service_unit_path="/etc/systemd/system/${service_name}.service"
  local cleanup_paths
  local cleanup_path

  if ! linux_manager_is_safe_systemd_service_name "${service_name}"; then
    printf 'unsafe systemd service name: %s\n' "${service_name}" >&2
    return 1
  fi

  linux_manager_systemctl_stop "${service_name}" || true
  linux_manager_systemctl_disable "${service_name}" || true

  if ! rm -f -- "${service_unit_path}"; then
    printf 'failed to remove systemd unit: %s\n' "${service_unit_path}" >&2
    return 1
  fi

  linux_manager_systemctl_daemon_reload || true

  cleanup_paths="$(linux_manager_get_uninstall_cleanup_paths "${config_path}")" || return 1

  while IFS= read -r cleanup_path; do
    if [[ -z "${cleanup_path}" ]]; then
      continue
    fi

    if ! linux_manager_is_manager_owned_cleanup_path "${cleanup_path}" "${config_path}"; then
      printf 'refusing to clean unsafe path: %s\n' "${cleanup_path}" >&2
      return 1
    fi

    if ! rm -rf -- "${cleanup_path}"; then
      printf 'failed to clean path: %s\n' "${cleanup_path}" >&2
      return 1
    fi
  done <<< "${cleanup_paths}"
}

linux_manager_ensure_config() {
  local config_path="${1:-$(linux_manager_get_config_path)}"

  linux_manager_initialize_config_file "${config_path}"
}

linux_manager_handle_main_menu_choice() {
  local choice="${1:-}"
  local config_path="${2:-$(linux_manager_get_config_path)}"

  case "${choice}" in
    1)
      linux_manager_update_server "${config_path}"
      ;;
    2)
      linux_manager_update_mods "${config_path}"
      ;;
    3)
      linux_manager_start_server "${config_path}"
      ;;
    4)
      linux_manager_stop_server "${config_path}"
      ;;
    5)
      linux_manager_manage_steam_account_menu "${config_path}"
      ;;
    6)
      linux_manager_manage_mod_groups_menu "${config_path}"
      ;;
    7)
      linux_manager_manage_mods_menu "${config_path}"
      ;;
    8)
      linux_manager_remove_uninstall_menu "${config_path}"
      ;;
    9)
      linux_manager_manage_linux_service_tools_menu "${config_path}"
      ;;
    10)
      return 0
      ;;
    *)
      printf 'Unknown menu choice: %s\n' "${choice}" >&2
      return 1
      ;;
  esac
}

linux_manager_run_menu() {
  local config_path choice

  config_path="$(linux_manager_get_config_path)"
  linux_manager_ensure_config "${config_path}"

  while true; do
    linux_manager_clear_screen
    linux_manager_print_banner
    linux_manager_print_main_menu "${config_path}"
    printf '%s' 'Select an option: '

    if ! read -r choice; then
      return 0
    fi

    if ! linux_manager_handle_main_menu_choice "${choice}" "${config_path}"; then
      printf '%s\n' 'Action failed; returning to menu.' >&2
    fi

    if [[ "${choice}" == "10" ]]; then
      return 0
    fi

    printf '\n'
  done
}
