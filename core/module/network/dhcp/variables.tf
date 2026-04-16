variable enabled {
    type = bool
}
variable domain_name {
    type = string
}

variable domain_name_servers {
    type = list(string)
}

variable tags {
    type = map(string)
}

variable vpc_id {
    type = string
}

variable region {
    type = string
}

variable created_on {
    type = string
}