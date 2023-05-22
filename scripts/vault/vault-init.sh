#!/bin/sh

test $VAULT_HOST || VAULT_HOST=localhost
test $VAULT_PORT || VAULT_PORT=8200
VAULT_ADDRESS="http://$VAULT_HOST:$VAULT_PORT"

test $TARGET_DIR || TARGET_DIR=/scripts
test $VAULT_KEYS_FILE || VAULT_KEYS_FILE=$TARGET_DIR/private_keys

TOKENS_LIST_FILE=$TARGET_DIR/token.list

test -d $TARGET_DIR || mkdir -p $TARGET_DIR


function show_usage() {
	echo "Usage: ${0##*/} --(init|unseal|authorise|create-policies|create-tokens|create-secrets)" 
	echo -e "\t Example: ${0##*/} --init"
	echo -e "\t Example: ${0##*/} --unseal"
	echo -e "\t Example: ${0##*/} --authorise"
	echo -e "\t Example: ${0##*/} --create-policies"
	echo -e "\t Example: ${0##*/} --create-tokens"
	echo -e "\t Example: ${0##*/} --create-secrets"
}

function show_error() {
		local message="$1"; local funcname="$2"; local log_date=`date '+%Y/%m/%d:%H:%M:%S %Z'`
		echo -e "[ERROR.$funcname $log_date] $message" >&2
		err=1
}

function show_notice() {
		local message="$1"; local funcname="$2"; local log_date=`date '+%Y/%m/%d:%H:%M:%S %Z'`
		echo -e "\n[NOTICE.$funcname $log_date] $message"
}


function vault_init() {
	local err=0;

	show_notice "Vault init and save keys to file $VAULT_KEYS_FILE started."
	vault operator init --address=$VAULT_ADDRESS | grep -E 'Initial Root Token:|Unseal Key .:' > $VAULT_KEYS_FILE

	return $err;
}

function vault_unseal() {
	local err=0;
	test -f $VAULT_KEYS_FILE || { show_error "Vault keys file: $VAULT_KEYS_FILE doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Vault unseal started."
	list='1 2 3'
	for number in $list; do
		vault_unseal_key=`grep "Unseal Key $number" $VAULT_KEYS_FILE | awk -F':' '{print $2}' | tr '\n' ' ' | sed "s/ //g"`
		vault operator unseal -address=$VAULT_ADDRESS $vault_unseal_key
		echo
	done

	return $err;
}

function vault_authorise() {
	local err=0;
	test -f $VAULT_KEYS_FILE || { show_error "Vault keys file: $VAULT_KEYS_FILE doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Vault authorise with root token started."
	vault_root_token=`grep 'Root Token' $VAULT_KEYS_FILE | awk -F':' '{print $2}' | tr '\n' ' ' | sed "s/ //g"`

	vault login --address=$VAULT_ADDRESS $vault_root_token
}

function vault_create_policies() {
	local err=0;
	test -d $TARGET_DIR/policies || { show_error "Dir: $TARGET_DIR/policies doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Create Vault policies started."
	for policy in `ls -1 $TARGET_DIR/policies/ | grep '.hcl' | sed "s/\.hcl//g"`; do
		vault policy write --address=$VAULT_ADDRESS $policy $TARGET_DIR/policies/${policy}.hcl
	done

	return $err;
}

function vault_create_tokens() {
	local err=0;
	test -f $token_list || { show_error "Tokens file: $token_list doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Create Vault tokens started."

	for token in `cat $TOKENS_LIST_FILE | awk '{print $1}'`; do
		show_notice "Create token: $token"
		token_policy=`grep $token $TOKENS_LIST_FILE | awk '{print $2}' | sed "s/\,/ -policy=/g"`
		vault token create -id=$token -policy=$token_policy -ttl=168h --address=$VAULT_ADDRESS
		echo
	done

	return $err;
}

function vault_enable_secrets_storage() {
    show_notice "Check that KV secrets storage enabled"
    count=$(vault secrets list -address=$VAULT_ADDRESS | grep 'secret/' -c)

    if [ $count -eq "0" ] ; then
		show_notice "Initialize KV secrets storage"
        vault secrets enable -version=1 -path=secret -address=$VAULT_ADDRESS kv
	else
		show_notice "KV secrets storage enabled already."
	fi
}

function vault_create_secrets() {
	local err=0;
	test -d $TARGET_DIR/secrets || { show_error "Dir: $TARGET_DIR/secrets doesn't exist!" "$FUNCNAME"; return 1; }

	show_notice "Create Vault secrets started."

	for secret in `find $TARGET_DIR/secrets/ -iname '*.json' -type f ! -size 0 -print | sed "s!$TARGET_DIR/secrets/!!g" | sed "s/\.json//g"`; do
		vault write --address=$VAULT_ADDRESS secret/$secret @$TARGET_DIR/secrets/${secret}.json
	done

	return $err;
}

function vault_check() {
	local err=0; local check=0;
	one_try_timeout=1
	seconds_timeout=60

	seconds=`date +%s`
	endTime=$(( $(date +%s) + $seconds_timeout ))
	while [  $seconds -lt $endTime ]; do
		sleep $one_try_timeout
		seconds=`date +%s`

		show_notice "Seconds until timeout: $(( $(date +%s) - $endTime ))"
		nc -vz $VAULT_HOST $VAULT_PORT >/dev/null && \
		{ seconds=$(($endTime+1)); show_notice "Vault is available."; check=1; }
	done

	test $seconds -gt $endTime -a $check -ne 1 && \
	{ show_error "Something go wrong, during $seconds_timeout seconds vault doesn't available on $VAULT_ADDRESS" "$FUNCNAME"; return 1; }

	return $err;
}

function vault_check_init() {
	local err=0;

	show_notice "Starting check that Vault is initialised."
	vault operator init --address=$VAULT_ADDRESS -status
	result=$?
	if [ "${result}" -eq "2" ] ; then
		show_notice "Vault doesn't initialised, executing init."
		vault_init
	else
		show_notice "All OK Vault aleready initialised."
	fi

	return $err;
}

function vault_check_unseal() {
	local err=0;

	show_notice "Starting check that Vault is unsealed."
	vault status --address=$VAULT_ADDRESS
	result=$?
	if [ "${result}" -eq "2" ] ; then
		show_notice "Vault sealed, executing unseal."
		vault_unseal
	else
		show_notice "All OK Vault aleready unsealed."
	fi

	return $err;
}


#Check script usage
test $# -eq 1 || { show_error "Wrong script usage!" ""; show_usage; exit 1; }
test x"$1" == x"" && show_usage


test x"$1" = x"--init" && {

		show_notice "Vault init started."
		vault_check && \
		vault_check_init && \
		vault_check_unseal && \
		sleep 5 && vault_authorise && \
		vault_create_policies && \
		vault_create_tokens && \
		vault_enable_secrets_storage && \
		vault_create_secrets
}

test x"$1" = x"--unseal" && {
	vault_unseal
}

test x"$1" = x"--authorise" && {
	vault_authorise
}

test x"$1" = x"--create-policies" && {
	vault_create_policies
}

test x"$1" = x"--create-tokens" && {
	vault_create_tokens
}

test x"$1" = x"--create-secrets" && {
	vault_create_secrets
}
