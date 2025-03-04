require 'cocoapods'
require 'cocoapods-core'
require 'cocoapods/user_interface'
# require_relative '../config/podspec'
require_relative '../installer/concurrency'

module LgPodPlugin

  class ReleasePod < ExternalPod
    def initialize(target, name, hash, spec)
      @spec = spec
      @name = name
      @target = target
      @released_pod = true
      @checkout_options = hash
    end

    def self.check_release_pod_exist(name, requirements, spec, released_pod)
      is_exist, _, _ = (LCache.new.pod_cache_exist(name, requirements, spec, released_pod))
      return is_exist
    end

    def self.resolve_dependencies(lockfile, installer)
      installer.send(:resolve_dependencies)
      external_pods = LProject.shared.external_pods ||= {}
      analysis_result = installer.send(:analysis_result)
      return unless analysis_result
      root_specs = analysis_result.specifications.map(&:root).uniq
      root_specs = root_specs.reject! do |spec|
        spec_name = spec.send(:attributes_hash)["name"]
        external_pods[spec_name] || external_pods[spec_name.split("/").first]
      end unless external_pods.empty?
      return unless root_specs
      all_installers = Array.new
      root_specs.sort_by(&:name).each do |spec|
        attributes_hash = spec.send(:attributes_hash)
        next unless attributes_hash.is_a?(Hash)
        pod_name = attributes_hash["name"]
        source = attributes_hash['source']
        next unless source.is_a?(Hash)
        git = source["git"]
        tag = source["tag"]
        http = source["http"]
        if http
          if http.include?("github.com") && http.include?("releases/download")
            http = "https://ghproxy.com/" + http
            source["http"] = http
          end
          version = attributes_hash["version"] ||= ""
          requirements = {:http => http, :version => version}
        elsif git && tag
          tag = tag.to_s unless LUtils.is_a_string? tag
          requirements = { :git => git, :tag => tag }
        else
          next
        end
        next if check_release_pod_exist(pod_name, requirements, spec, true)
        LProject.shared.cache_specs[pod_name] = spec
        release_pod = ReleasePod.new(nil, pod_name, requirements, spec)
        pod_install = LgPodPlugin::LPodInstaller.new
        download_params = pod_install.install(release_pod)
        all_installers.append pod_install if download_params
      end
      # 通过 swift 可执行文件进行异步下载任务
      LgPodPlugin::Concurrency.async_download_pods all_installers
    end
    

    def self.download_dependencies(installer)
      installer.download_dependencies
      installer.send(:validate_targets)
      installer.send(:clean_sandbox)
      skip_pods_project_generation = installer.send(:installation_options).send(:skip_pods_project_generation)
      if skip_pods_project_generation
        installer.show_skip_pods_project_generation_message
        installer.send(:run_podfile_post_install_hooks)
      else
        installer.integrate
      end
      installer.send(:write_lockfiles)
      installer.send(:perform_post_install_actions)
    end

    def self.lockfile_missing_pods(pods, lockfile)
      lockfile_roots = lockfile.pod_names.map { |pod| Pod::Specification.root_name(pod) }
      pods.map { |pod| Pod::Specification.root_name(pod) }.uniq - lockfile_roots
    end

    # Check if all given pods are installed
    #
    def self.verify_pods_are_installed!(pods, lockfile)
      missing_pods = lockfile_missing_pods(pods, lockfile)

      unless missing_pods.empty?
        message = if missing_pods.length > 1
                    "Pods `#{missing_pods.join('`, `')}` are not " \
                          'installed and cannot be updated'
                  else
                    "The `#{missing_pods.first}` Pod is not installed " \
                          'and cannot be updated'
                  end
        raise Pod::Informative, message
      end
    end

    def self.verify_lockfile_exists!(lockfile)
      unless lockfile
        raise Pod::Informative, "No `Podfile.lock' found in the project directory, run `pod install'."
      end
    end
    
    def self.install_release_pod(update, repo_update, verbose, clean_install)
      #切换工作目录到当前工程下, 开始执行pod install
      workspace = LProject.shared.workspace
      FileUtils.chdir(workspace)
      # 安装 release_pod
      LgPodPlugin.log_blue "Pre-downloading Release Pods"
      Pod::Config.instance.verbose = verbose
      pods_path = LProject.shared.workspace.join('Pods')
      podfile = LProject.shared.podfile
      lockfile_path = workspace.join("Podfile.lock")
      lockfile =   Pod::Lockfile.from_file(lockfile_path)
      sandbox = Pod::Sandbox.new(pods_path)
      installer = Pod::Installer.new(sandbox, podfile, lockfile)
      installer.repo_update = repo_update
      if update
        pods = LProject.shared.external_pods.keys
        begin
          self.verify_lockfile_exists!(lockfile)
          self.verify_pods_are_installed!(pods, lockfile)
          if pods.empty?
            installer.update = true
          else
            installer.update = { :pods => pods }
          end
        rescue
          installer.update = false
        end
      else
        installer.update = false
      end
      installer.deployment = false
      installer.clean_install = clean_install
      installer.prepare
      resolve_dependencies(lockfile, installer)
      download_dependencies(installer)
    end

  end

end
