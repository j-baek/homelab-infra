# Mocked planning catches rendering/type regressions without touching libvirt.
mock_provider "libvirt" {}

variables {
  k3s_token           = "test-only-placeholder-not-a-real-secret-0123456789"
  ssh_public_key_path = "tests/fixtures/id_ed25519.pub"
}

run "default_cluster" {
  command = plan

  assert {
    condition     = length(libvirt_domain.node) == 3 && local.server_ip == "192.168.100.10"
    error_message = "Default topology must contain three guests and the expected server address."
  }
  assert {
    condition     = yamldecode(yamldecode(libvirt_cloudinit_disk.node["server"].user_data).write_files[0].content)["write-kubeconfig-mode"] == "0600"
    error_message = "Server administrator credentials must not be world-readable."
  }
  assert {
    condition     = yamldecode(yamldecode(libvirt_cloudinit_disk.node["agent-1"].user_data).write_files[0].content).server == "https://192.168.100.10:6443"
    error_message = "Agents must join the configured server."
  }
  assert {
    condition     = yamldecode(libvirt_cloudinit_disk.node["agent-1"].network_config).ethernets.eth0.match.macaddress == var.nodes["agent-1"].mac
    error_message = "Guest networking must match the reserved MAC address."
  }
}

run "reject_example_token" {
  command = plan
  variables {
    k3s_token = "REPLACE_WITH_A_RANDOM_SECRET_AT_LEAST_32_CHARACTERS"
  }
  expect_failures = [var.k3s_token]
}
