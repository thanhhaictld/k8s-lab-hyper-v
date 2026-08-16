output "nodes" {
  value = {
    for name, node in local.nodes :
    name => {
      ip   = node.ip
      role = node.role
    }
  }
}

output "ssh_examples" {
  value = [
    for name, node in local.nodes :
    "ssh ansible@${node.ip}"
  ]
}
