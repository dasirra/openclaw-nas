#!/usr/bin/env bash
# installer/ollama.sh — Ollama LLM provider setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: OLLAMA_SETUP_STATUS (validated|unverified|skipped)

OLLAMA_SETUP_STATUS="skipped"

_OLLAMA_DEFAULT_LOCAL_HOST="http://host.docker.internal:11434"
_OLLAMA_CLOUD_HOST="https://ollama.com"

# run_ollama — choose local or cloud Ollama, verify reachability, pick a model.
# Writes OLLAMA_HOST, OLLAMA_API_KEY, OLLAMA_MODEL to .env.
run_ollama() {
  local existing_host existing_key existing_model
  existing_host=$(env_get "OLLAMA_HOST")
  existing_key=$(env_get "OLLAMA_API_KEY")
  existing_model=$(env_get "OLLAMA_MODEL")

  print_info "Ollama can run through the cloud (default) or locally."
  echo ""

  # Cloud is the default. Switch to Local only if the user explicitly picks it,
  # or if an existing .env clearly points to a local host without an API key.
  local mode_default="Cloud"
  if [ -z "$existing_key" ] && [ -n "$existing_host" ]; then
    case "$existing_host" in
      https://ollama.com*) mode_default="Cloud" ;;
      *)                   mode_default="Local" ;;
    esac
  fi

  local mode
  mode=$(printf 'Cloud\nLocal' | gum choose --header "Where does Ollama run? (current: $mode_default)")
  [ -z "$mode" ] && mode="$mode_default"

  local host api_key
  case "$mode" in
    Cloud)
      host="${existing_host:-$_OLLAMA_CLOUD_HOST}"
      case "$host" in http://*|https://*) ;; *) host="$_OLLAMA_CLOUD_HOST" ;; esac
      print_info "Get an API key at https://ollama.com/settings/keys"
      local key_prompt="Ollama Cloud API key"
      [ -n "$existing_key" ] && key_prompt="$key_prompt (current: $(mask_token "$existing_key"))"
      api_key=$(gum_input_password "$key_prompt")
      [ -z "$api_key" ] && api_key="$existing_key"
      if [ -z "$api_key" ]; then
        print_error "API key required for Ollama Cloud."
        OLLAMA_SETUP_STATUS="skipped"
        return 0
      fi
      host=$(gum_input "Ollama Cloud URL" "$host")
      [ -z "$host" ] && host="$_OLLAMA_CLOUD_HOST"
      ;;
    Local|*)
      host="${existing_host:-$_OLLAMA_DEFAULT_LOCAL_HOST}"
      case "$host" in https://ollama.com*) host="$_OLLAMA_DEFAULT_LOCAL_HOST" ;; esac
      host=$(gum_input "Ollama host URL" "$host")
      [ -z "$host" ] && host="$_OLLAMA_DEFAULT_LOCAL_HOST"
      api_key=""
      ;;
  esac

  case "$host" in
    http://*|https://*) ;;
    *)
      print_error "URL must start with http:// or https://"
      OLLAMA_SETUP_STATUS="skipped"
      return 0
      ;;
  esac

  print_info "Checking connectivity to $host ..."
  local curl_args=(-sf --max-time 10 "$host/api/tags")
  [ -n "$api_key" ] && curl_args+=(-H "Authorization: Bearer $api_key")
  local response
  if ! response=$(curl "${curl_args[@]}" 2>/dev/null); then
    print_error "Could not reach Ollama at $host"
    [ -n "$api_key" ] && print_info "Check your API key and network."
    [ -z "$api_key" ] && print_info "Make sure Ollama is running (e.g. 'ollama serve')."
    if gum_confirm "Save anyway and continue?"; then
      env_set "OLLAMA_HOST" "$host"
      env_set "OLLAMA_API_KEY" "$api_key"
      [ -n "$existing_model" ] || env_set "OLLAMA_MODEL" ""
      OLLAMA_SETUP_STATUS="unverified"
      print_warn "Saved unverified. The gateway will fail to use Ollama until it's reachable."
    else
      OLLAMA_SETUP_STATUS="skipped"
    fi
    return 0
  fi

  print_success "Connected to Ollama at $host"

  local models
  models=$(echo "$response" | jq -r '.models[].name // empty' 2>/dev/null)

  if [ -z "$models" ]; then
    print_warn "No models available on this Ollama instance."
    [ -z "$api_key" ] && print_info "Pull one on the host with: ollama pull <model>"
    echo ""
    local manual_model
    manual_model=$(gum_input "Model name to configure anyway (e.g. llama3.1:8b)" "${existing_model:-llama3.1:8b}")
    [ -z "$manual_model" ] && manual_model="${existing_model:-llama3.1:8b}"
    env_set "OLLAMA_HOST" "$host"
    env_set "OLLAMA_API_KEY" "$api_key"
    env_set "OLLAMA_MODEL" "$manual_model"
    OLLAMA_SETUP_STATUS="unverified"
    print_warn "Saved. Ensure the model is available, or the gateway will fail on first request."
    return 0
  fi

  echo ""
  print_info "Available models:"
  echo "$models" | sed 's|^|  • |'
  echo ""

  local chosen
  chosen=$(echo "$models" | gum choose --header "Select default model for all agents:")
  if [ -z "$chosen" ]; then
    chosen="${existing_model:-$(echo "$models" | head -n 1)}"
    print_info "No selection. Using: $chosen"
  fi

  env_set "OLLAMA_HOST" "$host"
  env_set "OLLAMA_API_KEY" "$api_key"
  env_set "OLLAMA_MODEL" "$chosen"
  OLLAMA_SETUP_STATUS="validated"
  print_success "Ollama configured: $host (default model: $chosen)"

  echo ""
  print_info "To use a different model for a specific agent, set OLLAMA_MODEL_<AGENT>"
  print_info "in .env (e.g. OLLAMA_MODEL_SCOUTER=qwen2.5:14b). Leave unset to use the default."
}
