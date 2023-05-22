backend "consul" {
	address = "consul:8500"
	disable_registration = "true"
}

listener "tcp" {
	address = "0.0.0.0:8200"
	tls_disable = 1
}

ui = true
disable_mlock = true
