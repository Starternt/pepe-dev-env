path "secret/s3" {
    capabilities = ["read"]
}

path "secret/posts-database" {
    capabilities = ["read", "list"]
}

path "secret/jwt" {
    capabilities = ["read"]
}