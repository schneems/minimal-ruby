require_relative "../spec_helper.rb"

# Log Dir.chdir
# Log ENV setting and getting
#
RSpec.describe "bash_functions.sh" do
  def bash_functions_file
    root_dir.join("bin", "support", "bash_functions.sh")
  end

  def exec_with_bash_functions(code, stack: "heroku-18")
    contents = <<~EOM
      #! /usr/bin/env bash
      set -eu

      STACK="#{stack}"

      source #{bash_functions_file}
      #{code}
    EOM

    file = Tempfile.new
    file.write(contents)
    file.close
    FileUtils.chmod("+x", file.path)

    out = nil
    success = false
    begin
      Timeout.timeout(60) do
        out = `#{file.path} 2>&1`.strip
        success = $?.success?
      end
    rescue Timeout::Error
      out = "Command timed out"
      success = false
    end
    unless success
      message = <<~EOM
        Expected running script to succeed, but it did not

        Output:

          #{out}

        Script name: #{file.path}
        Contents:

        #{contents.lines.map.with_index { |line, number| "  #{number.next} #{line.chomp}"}.join("\n") }

      EOM

      raise message
    end
    out
  end

  it "Downloads a ruby binary" do
    Dir.mktmpdir do |dir|
      exec_with_bash_functions <<~EOM

        download_ruby "2.6.6" "#{dir}"
      EOM

      entries = Dir.entries(dir) - [".", ".."]

      expect(entries.sort).to eq(["bin", "include", "lib", "ruby.tgz", "share"])
    end
  end

  it "parses toml files" do
    out = exec_with_bash_functions <<~EOM
      ruby_version_from_toml "#{root_dir.join("buildpack.toml")}"
    EOM

    expect(out).to eq(HerokuBuildpackRuby::RubyDetectVersion::DEFAULT)
  end

  it "downloads ruby to BUILDPACK_DIR vendor directory" do
    Dir.mktmpdir do |dir|
      dir = Pathname.new(dir)

      exec_with_bash_functions(<<~EOM, stack: "heroku-18")
        BUILDPACK_DIR="#{dir}"
        download_ruby_version_to_buildpack_vendor "2.6.6"
      EOM

      expect(dir.entries.map(&:to_s)).to include("vendor")
      expect(dir.join("vendor").entries.map(&:to_s)).to include("ruby")
      expect(dir.join("vendor", "ruby").entries.map(&:to_s)).to include("heroku-18")
      expect(dir.join("vendor", "ruby", "heroku-18", "bin").entries.map(&:to_s)).to include("ruby")
    end
  end

  it "bootstraps ruby using toml file" do
    Dir.mktmpdir do |dir|
      dir = Pathname.new(dir)

      FileUtils.cp(
        root_dir.join("buildpack.toml"), # From
        dir.join("buildpack.toml") # To
      )

      exec_with_bash_functions <<~EOM
        BUILDPACK_DIR="#{dir}"
        bootstrap_ruby_to_buildpack_dir
      EOM

      expect(dir.entries.map(&:to_s)).to include("vendor")
      expect(dir.join("vendor").entries.map(&:to_s)).to include("ruby")
      expect(dir.join("vendor", "ruby").entries.map(&:to_s)).to include("heroku-18")
      expect(dir.join("vendor", "ruby", "heroku-18", "bin").entries.map(&:to_s)).to include("ruby")
    end
  end
end

