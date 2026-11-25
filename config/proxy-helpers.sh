# >>> proxy helpers >>>
proxy_on() {
  export http_proxy=http://@@PROXY_ADDR@@
  export https_proxy=http://@@PROXY_ADDR@@
  echo "proxy on: $http_proxy"
}

proxy_off() {
  unset http_proxy https_proxy
  echo "proxy off"
}

conda_proxy_on() {
  conda config --set proxy_servers.http http://@@PROXY_ADDR@@
  conda config --set proxy_servers.https http://@@PROXY_ADDR@@
  echo "conda proxy on: http://@@PROXY_ADDR@@"
}

conda_proxy_off() {
  conda config --remove-key proxy_servers 2>/dev/null
  conda clean -i -y
  echo "conda proxy off"
}
# <<< proxy helpers <<<
