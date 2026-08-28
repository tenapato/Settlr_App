# frozen_string_literal: true

require "yaml"
require "open3"

workflow_path = File.expand_path("../.github/workflows/testflight.yml", __dir__)
abort "Missing #{workflow_path}" unless File.file?(workflow_path)

workflow = YAML.safe_load(File.read(workflow_path), aliases: false)
triggers = workflow.fetch("on", workflow[true])
abort "Workflow must deploy pushes to main" unless triggers.dig("push", "branches") == ["main"]
abort "Workflow must support manual deployment" unless triggers.key?("workflow_dispatch")

deploy = workflow.dig("jobs", "deploy")
abort "Missing deploy job" unless deploy
abort "Deploy job must use macos-26" unless deploy["runs-on"] == "macos-26"

steps = deploy.fetch("steps")
steps.each do |step|
  next unless step["run"]

  _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: step["run"])
  abort "Invalid shell syntax in #{step.fetch('name')}: #{stderr}" unless status.success?
end

step_names = steps.map { |step| step["name"] }.compact
required_steps = [
  "Validate deployment secrets",
  "Run tests",
  "Install signing assets",
  "Install App Store Connect API key",
  "Archive app",
  "Upload to TestFlight",
  "Clean up signing assets"
]
missing_steps = required_steps - step_names
abort "Missing deployment steps: #{missing_steps.join(', ')}" unless missing_steps.empty?

cleanup = steps.find { |step| step["name"] == "Clean up signing assets" }
abort "Signing cleanup must run even after failure" unless cleanup["if"] == "always()"

workflow_text = File.read(workflow_path)
required_secrets = %w[
  APP_STORE_CONNECT_API_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID
  APP_STORE_CONNECT_API_KEY_BASE64
  APPLE_DISTRIBUTION_CERTIFICATE_BASE64
  APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64
]
missing_secrets = required_secrets.reject do |secret|
  workflow_text.include?("secrets.#{secret}")
end
abort "Missing secret references: #{missing_secrets.join(', ')}" unless missing_secrets.empty?

puts "TestFlight workflow contract is valid"
