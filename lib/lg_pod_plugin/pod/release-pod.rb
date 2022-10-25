require 'cocoapods'
require 'cocoapods-core'

module LgPodPlugin

  class ReleasePod < ExternalPod

    def initialize(target, name, spec, hash)
      @spec = spec
      @name = name
      @target = target
      @released_pod = true
      @checkout_options = hash
    end

    def self.check_release_pod_exist(workspace, name, requirements, spec, released_pod)
      return !(LCache.new.find_pod_cache(name, requirements, spec, released_pod))
    end

    def self.resolve_dependencies(workspace, podfile, lockfile, installer, external_pods)
      installer.resolve_dependencies
      analysis_result = installer.send(:analysis_result)
      return unless analysis_result
      root_specs = analysis_result.specifications.map(&:root).uniq
      root_specs = root_specs.reject! do |spec|
        spec_name = spec.send(:attributes_hash)["name"]
        external_pods[spec_name] || external_pods[spec_name.split("/").first]
      end unless external_pods.empty?
      return unless root_specs
      root_specs.sort_by(&:name).each do |spec|
        attributes_hash = spec.send(:attributes_hash)
        next unless attributes_hash.is_a?(Hash)
        pod_name = attributes_hash["name"]
        pod_version = attributes_hash["version"]
        source = attributes_hash['source']
        next unless source.is_a?(Hash)
        git = source["git"]
        tag = source["tag"]
        next unless (git && tag) && (git.include?("https://github.com"))
        checksum = spec.send(:checksum)
        requirements = { :git => git, :tag => tag}
        pod_exist = check_release_pod_exist(workspace, pod_name, requirements, spec, true)
        if lockfile && checksum
          internal_data = lockfile.send(:internal_data)
          lock_checksums = internal_data["SPEC CHECKSUMS"] ||= {}
          lock_checksum = lock_checksums[pod_name]
          next if (lock_checksum == checksum) && (pod_exist)
        else
          next if pod_exist
        end
        release_pod = ReleasePod.new(nil, pod_name, spec, requirements)
        LgPodPlugin::Installer.new.install release_pod
      end
    end

    def self.dependencies(installer)
      installer.download_dependencies
      installer.send(:validate_targets)
      installation_options = installer.send(:installation_options)
      skip_pods_project_generation = installation_options.send(:skip_pods_project_generation)
      if skip_pods_project_generation
        installer.show_skip_pods_project_generation_message
      else
        installer.integrate
      end
      installer.send(:write_lockfiles)
      installer.send(:perform_post_install_actions)
    end

    def self.install_release_pod(update, repo_update)
      #切换工作目录到当前工程下, 开始执行pod install
      workspace = LProject.shared.workspace
      FileUtils.chdir(workspace)
      # 安装 relase_pod
      LgPodPlugin.log_green "Pre-downloading Release Pods"
      Pod::Config.instance.verbose = true
      pods_path = LProject.shared.workspace.join('Pods')
      podfile = LProject.shared.podfile
      lockfile = LProject.shared.lockfile
      sandobx = Pod::Sandbox.new(pods_path)
      installer = Pod::Installer.new(sandobx, podfile, lockfile)
      installer.repo_update = repo_update
      external_pods = LProject.shared.external_pods
      if update
        # if external_pods.empty?
        #   installer.update = true
        # else
        #   pods = LRequest.shared.libs.merge!(local_pods)
        #   installer.update = { :pods => pods.keys }
        # end
        installer.update = true
      else
        installer.update = false
      end
      installer.deployment = false
      installer.clean_install = false
      installer.prepare
      resolve_dependencies(workspace, podfile, lockfile, installer, external_pods)
      dependencies(installer)
    end

  end

end
