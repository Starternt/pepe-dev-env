#!/bin/sh

test $CONSUL_HOST || CONSUL_HOST=localhost
test $CONSUL_PORT || CONSUL_PORT=8500
CONSUL_ADDRESS="http://$CONSUL_HOST:$CONSUL_PORT"

test $TARGET_DIR || TARGET_DIR=/scripts

test $CDN_URL || CDN_URL=http://localhost:1080/static/

function show_error() {
		local message="$1"; local funcname="$2"; local log_date=`date '+%Y/%m/%d:%H:%M:%S %Z'`
		echo -e "[ERROR.$funcname $log_date] $message" >&2
		err=1
}

function show_notice() {
		local message="$1"; local funcname="$2"; local log_date=`date '+%Y/%m/%d:%H:%M:%S %Z'`
		echo -e "[NOTICE.$funcname $log_date] $message"
}

function consul_wait() {
    while ! nc -z $CONSUL_HOST $CONSUL_PORT; do echo 'Wait Consul to startup...' && sleep 0.1; done;
    sleep 5
}

function consul_fill_kv() {
	local err=0;
	test -d $TARGET_DIR/kv || { show_error "Dir: $TARGET_DIR/kv doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Fill Consul key/value storage."

	consul kv put -http-addr=$CONSUL_ADDRESS "saas/settings/cdn_url" "$CDN_URL"

	for key in `find $TARGET_DIR/kv/ -iname '*.json' -type f ! -size 0 -print | sed "s!$TARGET_DIR/kv/!!g" | sed "s/\.json//g"`; do
		consul kv put -http-addr=$CONSUL_ADDRESS $key @$TARGET_DIR/kv/${key}.json
	done

	return $err;
}

consul_wait
consul_fill_kv
