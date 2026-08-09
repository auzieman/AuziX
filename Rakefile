require "fileutils"

ROOT = File.expand_path(__dir__)

namespace :source do
  desc "Materialize a Debian source package into an AUZiX source-port structure"
  task :port, [:package] do |_task, args|
    package = args[:package] || ENV["PACKAGE"]
    abort "usage: rake source:port[debian-package] or PACKAGE=debian-package rake source:port" if package.nil? || package.empty?
    sh File.join(ROOT, "scripts", "rake-auzix-source-port.sh"), package
  end

  desc "Run hardwired donor-path scan for a materialized source port"
  task :path_hunt, [:package] do |_task, args|
    package = args[:package] || ENV["PACKAGE"]
    abort "usage: rake source:path_hunt[debian-package] or PACKAGE=debian-package rake source:path_hunt" if package.nil? || package.empty?
    sh File.join(ROOT, "scripts", "rake-auzix-source-port.sh"), package, "path-hunt"
  end

  desc "Install Debian build dependencies for a source package on the current builder"
  task :build_deps, [:package] do |_task, args|
    package = args[:package] || ENV["PACKAGE"]
    abort "usage: rake source:build_deps[debian-package] or PACKAGE=debian-package rake source:build_deps" if package.nil? || package.empty?
    sh File.join(ROOT, "scripts", "rake-auzix-source-port.sh"), package, "build-deps"
  end

  desc "Print the AUZiX build plan mined from Debian source metadata"
  task :build_plan, [:package] do |_task, args|
    package = args[:package] || ENV["PACKAGE"]
    abort "usage: rake source:build_plan[debian-package] or PACKAGE=debian-package rake source:build_plan" if package.nil? || package.empty?
    sh File.join(ROOT, "scripts", "rake-auzix-source-port.sh"), package, "build-plan"
  end

  desc "Proof-check Debian's own binary build recipe for a materialized source port"
  task :debian_build, [:package] do |_task, args|
    package = args[:package] || ENV["PACKAGE"]
    abort "usage: rake source:debian_build[debian-package] or PACKAGE=debian-package rake source:debian_build" if package.nil? || package.empty?
    sh File.join(ROOT, "scripts", "rake-auzix-source-port.sh"), package, "debian-build"
  end
end
