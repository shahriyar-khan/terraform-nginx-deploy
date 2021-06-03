variable "region" {
    default = "us-east-1"
}
variable "access_key" {
    type = string
}
variable "secret_key" {
    type = string
}
variable "AMI" {
    type = map(string)
    default = {
        us-east-1 = "ami-0803a1230fe30f21d"
    }
}
variable "all_ipv4" {
    default = "0.0.0.0/0"
}
variable "all_ipv6" {
    default = "::/0"
}
variable "my_ip_cidr" {
    type = string
}
