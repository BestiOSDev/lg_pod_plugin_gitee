require 'cocoapods-core'
require_relative 'log'
require_relative 'l_util'

module LgPodPlugin

  class LockfileModel
    attr_accessor :lockfile
    attr_accessor :release_pods
    attr_accessor :external_sources_data
    attr_accessor :checkout_options_data

    def initialize
    end

    def self.from_file(path)
      return nil unless path.exist?
      begin
        lockfile = Pod::Lockfile.from_file(path)
      rescue => exception
        LgPodPlugin.log_red exception
        return nil
      end
      release_pods = Hash.new
      pods = lockfile.send(:generate_pod_names_and_versions)
      pods.each do |element|
        if LUtils.is_a_string?(element) || element.is_a?(Hash)
          key = element.is_a?(Hash) ? element.keys.first : element
          next unless key
          pod_name = LUtils.pod_real_name(key.split(" ").first) if key.include?(" ")
          tag = key[/(?<=\().*?(?=\))/]
          release_pods[pod_name] = tag
        else
          next
        end
      end
      lockfile_model = LockfileModel.new
      lockfile_model.lockfile = lockfile
      lockfile_model.release_pods = release_pods
      lockfile_model.checkout_options_data = lockfile.send(:checkout_options_data)
      lockfile_model.external_sources_data = lockfile.send(:external_sources_data)
      lockfile_model
    end

    def checkout_options_for_pod_named(name)
      checkout_options = @lockfile.checkout_options_for_pod_named(self.name)
      return checkout_options ||= {}
    end


  end
end