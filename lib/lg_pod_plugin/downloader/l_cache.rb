# require 'git'
require 'cocoapods/downloader'
require 'cocoapods/downloader/cache'
require 'cocoapods/downloader/response'
require 'cocoapods/downloader/request'

module LgPodPlugin

  class LCache

    def initialize
    end

    public
    def pod_cache_exist(name, options, spec = nil, released_pod = false)
      # 参数为空不执行下载任务, 交给 cocoapods 处理下载
      if options.nil?
        return   [true, nil, nil]
      end

      destination, cache_pod_spec = self.find_pod_cache name, options, spec, released_pod
      lock_temp_file = destination.to_path+ ".lock"
      if File.exist?(lock_temp_file)
        FileUtils.rm_rf lock_temp_file
      end
      if (File.exist?(destination) && !destination.children.empty?) && cache_pod_spec.exist?
        return [true, destination, cache_pod_spec]
      else
        return [false, destination, cache_pod_spec]
      end
    end

    #判断缓存是否存在且有效命中缓存
    public
    def find_pod_cache(name, options, spec = nil, released_pod = false)
      hash_map = Hash.new.merge!(options)
      if hash_map.has_key?(:version)
        hash_map.delete(:version)
      end
      request = LCache.download_request(name, hash_map, spec, released_pod)
      destination = LCache.path_for_pod(request)
      cache_pod_spec = LCache.path_for_spec(request)
      [destination, cache_pod_spec]
    end

    def self.root_path
      path = File.join(Dir.home, "Library/Caches/CocoaPods/Pods")
      Pathname(path)
    end

    def self.download_request(name, params, spec = nil, released_pod = false)
      if released_pod
        Pod::Downloader::Request.new(spec: spec, released: true , name: name, params: params)
      else
        Pod::Downloader::Request.new(spec: nil, released: false , name: name, params: params)
      end
    end
    #MARK - 缓存方法
    def self.path_for_pod(request, slug_opts = {})
      root = self.root_path
      root + request.slug(**slug_opts)
    end

    def self.path_for_spec(request, slug_opts = {})
      root = self.root_path
      path = root + 'Specs' + request.slug(**slug_opts)
      Pathname.new(path.to_path + '.podspec.json')
    end

    # def self.cached_spec(request)
    #   path = path_for_spec(request)
    #   path.file? && Specification.from_file(path)
    # rescue JSON::ParserError
    #   nil
    # end

    def self.get_local_spec(request, target)
      result = Pod::Downloader::Response.new
      result.location = target
      if request.released_pod?
        result.spec = request.spec
        local_specs = { request.name => request.spec }
        return [request, local_specs]
      else
        local_specs = {}
        pods_pecs = Pod::Sandbox::PodspecFinder.new(target).podspecs
        pods_pecs[request.name] = request.spec if request.spec
        pods_pecs.each do |name, spec|
          if request.name == name
            result.spec = spec
            local_specs[request.name] = spec
          end
        end
      end
      [result, local_specs]
    end

    def self.group_subspecs_by_platform(spec)
      specs_by_platform = {}
      [spec, *spec.recursive_subspecs].each do |ss|
        ss.available_platforms.each do |platform|
          specs_by_platform[platform] ||= []
          specs_by_platform[platform] << ss
        end
      end
      specs_by_platform
    end

    def self.copy_and_clean(source, destination, spec)
      specs_by_platform = group_subspecs_by_platform(spec)
      destination.parent.mkpath
      self.write_lock(destination) do
        Pod::Executable.execute_command('rsync', ['-a', '--exclude=.git/fsmonitor--daemon.ipc', '--delete', "#{source}/", destination])
        Pod::Installer::PodSourcePreparer.new(spec, destination).prepare!
        Pod::Sandbox::PodDirCleaner.new(destination, specs_by_platform).clean!
      end
    end

    def self.clean_pod_unused_files(destination, spec)
      specs_by_platform = group_subspecs_by_platform(spec)
      destination.parent.mkpath
      self.write_lock(destination) do
        Pod::Installer::PodSourcePreparer.new(spec, destination).prepare!
        Pod::Sandbox::PodDirCleaner.new(destination, specs_by_platform).clean!
      end
    end

    def self.write_lock(location, &block)
      Pod::Downloader::Cache.lock(location, File::LOCK_SH, &block)
    end

    public
    def self.write_spec(spec, path)
      path.dirname.mkpath
      Pod::Downloader::Cache.write_lock(path) do
        path.open('w') { |f|
          f.write spec.to_pretty_json
        }
      end
    end

    # 拷贝 pod 缓存文件到 sandbox
    public
    def self.cache_pod(name, target, options = {}, spec = nil, released_pod = false)
      checkout_options = Hash.new.deep_merge(options).reject do |key, val|
        !key || !val
      end
      request = LCache.download_request(name, checkout_options, spec, released_pod)
      _, pods_pecs = get_local_spec(request, target)
      pods_pecs.each do |_, s_spec|
        destination = path_for_pod(request, :name => name, :params => checkout_options)
        if !File.exist?(destination) || destination.children.empty?
          LgPodPlugin.log_green "Copying #{name} from `#{target}` to `#{destination}` "
          copy_and_clean(target, destination, s_spec)
        end
        cache_pod_spec = path_for_spec(request, :name => name, :params => checkout_options)
        unless File.exist?(cache_pod_spec)
          write_spec(s_spec, cache_pod_spec)
        end
      end

    end

  end

end
