start-openresty:
	 docker build --rm -t ngx-red . && docker run --rm -p 8088:80 --name ngx-red ngx-red:latest

start-nginx:
	docker build --rm -t ngx-red -f nginx.Dockerfile && docker run --rm -p 8088:80 --name ngx-red ngx-red:latest

test:
	hurl --verbose --test tests/cases.hurl

vendor-homebrew:
	luarocks install --lua-dir=/opt/homebrew/opt/luajit --tree ./src/vendor --no-doc --only-deps ./rockspec/red-git-1.rockspec
	luarocks install --lua-dir=/opt/homebrew/opt/luajit --tree ./src/vendor --no-doc ./rockspec/xml2lua-1.6-1.rockspec
	luarocks install --lua-dir=/opt/homebrew/opt/luajit --tree ./src/vendor --no-doc ./rockspec/lua-resty-core-0.1.21-1.rockspec
	luarocks install --lua-dir=/opt/homebrew/opt/luajit --tree ./src/vendor --no-doc ./rockspec/lua-resty-lrucache-0.10-1.rockspec
