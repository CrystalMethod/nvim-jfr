--- Minimal headless checks for nvim-jfr.project.
--
-- Run:
--   nvim --headless -u NONE -c "set rtp+=." -c "lua assert(require('nvim-jfr.project_spec').run())" -c "qa"

local M = {}

local project = require("nvim-jfr.project")

M.run = function()
  -- Basic smoke: module loads and get_root returns nil/str without error.
  local root = project.get_root(0)
  assert(root == nil or type(root) == "string")

  -- Cache clear should not error.
  project.clear_root_cache()
  project.clear_cache()

  -- POM parsing
  local parsed = project._parse_pom(table.concat({
    "<project>",
    "  <modelVersion>4.0.0</modelVersion>",
    "  <groupId>com.example</groupId>",
    "  <artifactId>parent</artifactId>",
    "  <packaging>pom</packaging>",
    "  <modules>",
    "    <module>api</module>",
    "    <module>service</module>",
    "  </modules>",
    "</project>",
  }, "\n"))
  assert(parsed.group_id == "com.example")
  assert(parsed.artifact_id == "parent")
  assert(parsed.packaging == "pom")
  assert(#parsed.modules == 2)

  -- Gradle settings parsing (Groovy)
  local g = project._parse_gradle_settings(table.concat({
    "rootProject.name = 'demo'",
    "include ':app', ':lib'",
    "// include ':ignored'",
  }, "\n"))
  assert(g.root_name == "demo")
  assert(#g.includes == 2)
  assert(g.includes[1] == ":app")
  assert(g.includes[2] == ":lib")

  -- Gradle settings parsing (Kotlin DSL-ish)
  local k = project._parse_gradle_settings(table.concat({
    "rootProject.name = \"demo-kts\"",
    "include(\":a\", \"::b\")",
  }, "\n"))
  assert(k.root_name == "demo-kts")
  assert(#k.includes == 2)

  -- Gradle wrapper properties parsing
  local wp = project._parse_gradle_wrapper_properties(
    "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip\n"
  )
  assert(wp.distribution_url ~= nil)
  assert(wp.gradle_version == "8.7")

  return true
end

return M
