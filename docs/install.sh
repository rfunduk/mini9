#!/bin/sh
set -e

repo="rfunduk/mini9"
bin="mini9"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)

case "$os" in
  darwin)
    case "$arch" in
      arm64) target="darwin-arm64" ;;
      x86_64) target="darwin-x86_64" ;;
      *) echo "unsupported macOS arch: $arch"; exit 1 ;;
    esac
    ;;
  linux)
    case "$arch" in
      x86_64|amd64) target="linux-x86_64" ;;
      *) echo "unsupported Linux arch: $arch"; exit 1 ;;
    esac
    ;;
  *)
    echo "unsupported OS: $os"
    exit 1
    ;;
esac

home_local="$HOME/.local/bin"
home_bin="$HOME/bin"
usr_local="/usr/local/bin"

if echo "$PATH" | tr ':' '\n' | grep -qx "$home_local"; then
    install_dir="$home_local"
elif [ -d "$home_bin" ] && echo "$PATH" | tr ':' '\n' | grep -qx "$home_bin"; then
    install_dir="$home_bin"
elif [ -d "$usr_local" ] && [ -w "$usr_local" ]; then
    install_dir="$usr_local"
else
    install_dir="$home_local"
    mkdir -p "$install_dir"
    echo "warning: $install_dir is not in PATH"
    echo "Add this to your shell profile:"
    echo "  export PATH=\"$install_dir:\$PATH\""
fi

tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
      grep '"tag_name":' |
      sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$tag" ]; then
    echo "failed to find latest release"
    exit 1
fi

latest_version="${tag#v}"

if current=$(command -v "$bin" >/dev/null 2>&1 && "$bin" --version 2>/dev/null); then
    current=$(echo "$current" | tr -d '[:space:]')
    if [ "$current" = "$latest_version" ]; then
        echo "$bin $current is already the latest version"
        exit 0
    fi
fi

zip="$bin-$tag-$target.zip"
url="https://github.com/$repo/releases/download/$tag/$zip"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $zip ..."
curl -fsSL -o "$tmp/$zip" "$url"

unzip -q "$tmp/$zip" -d "$tmp"

mkdir -p "$install_dir"
install -m 755 "$tmp/$bin" "$install_dir/$bin"

echo "$bin $tag installed to $install_dir"
