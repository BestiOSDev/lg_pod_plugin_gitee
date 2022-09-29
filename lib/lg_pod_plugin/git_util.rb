require 'pp'
require 'git'
require_relative 'l_config'
require_relative 'l_util'
require_relative 'request'
require_relative 'l_cache'

module LgPodPlugin

  class LGitUtil

    REQUIRED_ATTRS ||= %i[git tag path name commit branch].freeze
    attr_accessor(*REQUIRED_ATTRS)

    def initialize(name, options = {})
      self.name = name
      self.git = options[:git]
      self.tag = options[:tag]
      self.path = options[:path]
      self.branch = options[:branch]
      self.commit = options[:commit]
    end

    # 从 GitLab下载 zip包
    # 根据branch 下载 zip 包
    def gitlab_download_branch_zip(path, temp_name)
      branch = self.branch ||= "master"
      file_name = "#{temp_name}.zip"
      token = LRequest.shared.config.access_token
      base_url = LRequest.shared.config.project.web_url
      project_name = LRequest.shared.config.project.path
      download_url = LUtils.get_gitlab_download_url(base_url, branch, nil, nil, project_name)
      unless download_url
        return self.git_clone_by_branch(path, temp_name)
      end
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, token, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("下载zip包失败, 尝试git clone #{self.git}")
        return self.git_clone_by_branch(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      new_file_name = "#{project_name}-#{branch}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_branch(path, temp_name)
      end
      path.join(new_file_name)
    end

    # 通过tag下载zip包
    def gitlab_download_tag_zip(path, temp_name)
      file_name = "#{temp_name}.zip"
      token = LRequest.shared.config.access_token
      base_url = LRequest.shared.config.project.web_url
      project_name = LRequest.shared.config.project.path
      download_url = LUtils.get_gitlab_download_url(base_url, nil, self.tag, nil, project_name)
      # 下载文件
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, token, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("下载zip包失败, 尝试git clone #{self.git}")
        return self.git_clone_by_tag(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      new_file_name = "#{project_name}-#{self.tag}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_tag(path, temp_name)
      end
      path.join(new_file_name)
    end

    # 通过 commit 下载zip包
    def gitlab_download_commit_zip(path, temp_name)
      file_name = "#{temp_name}.zip"
      token = LRequest.shared.config.access_token
      base_url = LRequest.shared.config.project.web_url
      project_name = LRequest.shared.config.project.path
      download_url = LUtils.get_gitlab_download_url(base_url, nil, nil, self.commit, project_name)
      # 下载文件
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, token, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_commit(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      new_file_name = "#{project_name}-#{self.commit}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_commit(path, temp_name)
      end
      path.join(new_file_name)
    end

    # 从 Github下载 zip 包
    # 根据branch 下载 zip 包
    def github_download_branch_zip(path, temp_name)
      file_name = "#{temp_name}.zip"
      branch = self.branch ||= "master"
      if self.git.include?(".git")
        base_url = self.git[0...self.git.length - 4]
      else
        base_url = self.git
      end
      project_name = base_url.split("/").last if base_url
      origin_url = base_url + "/archive/#{branch}.zip"
      download_url = "https://gh.api.99988866.xyz/#{origin_url}"
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, nil, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("下载zip包失败, 尝试git clone #{self.git}")
        return self.git_clone_by_branch(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      new_file_name = "#{project_name}-#{branch}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_branch(path, temp_name)
      end
      path.join(new_file_name)
    end

    # 通过tag下载zip包
    def github_download_tag_zip(path, temp_name)
      file_name = "#{temp_name}.zip"
      if self.git.include?(".git")
        base_url = self.git[0...self.git.length - 4]
      else
        base_url = self.git
      end
      project_name = base_url.split("/").last if base_url
      origin_url = base_url + "/archive/refs/tags/#{self.tag}.zip"
      download_url = "https://gh.api.99988866.xyz/#{origin_url}"
      # 下载文件
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, nil, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_tag(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      if self.tag.include?("v") && self.tag[0...1] == "v"
        this_tag = self.tag[1...self.tag.length]
      else
        this_tag = self.tag
      end
      new_file_name = "#{project_name}-#{this_tag}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_tag(path, temp_name)
      end
      path.join(new_file_name)
    end

    # 通过 commit 下载zip包
    def github_download_commit_zip(path, temp_name)
      file_name = "#{temp_name}.zip"
      if self.git.include?(".git")
        base_url = self.git[0...self.git.length - 4]
      else
        base_url = self.git
      end
      project_name = base_url.split("/").last if base_url
      origin_url = base_url + "/archive/#{self.commit}.zip"
      download_url = "https://gh.api.99988866.xyz/#{origin_url}"
      # 下载文件
      LgPodPlugin.log_blue "开始下载 => #{download_url}"
      LUtils.download_zip_file(download_url, nil, file_name)
      unless File.exist?(file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_commit(path, temp_name)
      end
      # 解压文件
      result = LUtils.unzip_file(path.join(file_name).to_path, "./")
      new_file_name = "#{project_name}-#{self.commit}"
      unless result && File.exist?(new_file_name)
        LgPodPlugin.log_red("正在尝试git clone #{self.git}")
        return self.git_clone_by_commit(path, temp_name)
      end
      path.join(new_file_name)
    end

    def git_clone_by_branch(path, temp_name)
      if self.git && self.branch
        LgPodPlugin.log_blue "git clone --depth=1 --branch #{self.branch} #{self.git}"
        system("git clone --depth=1 -b #{self.branch} #{self.git} #{temp_name}")
      else
        LgPodPlugin.log_blue "git clone --depth=1 #{self.git}"
        system("git clone --depth=1 #{self.git} #{temp_name}")
      end
      path.join(temp_name)
    end

    def git_clone_by_tag(path, temp_name)
      LgPodPlugin.log_blue "git clone --tag #{self.tag} #{self.git}"
      system("git clone --depth=1 -b #{self.tag} #{self.git} #{temp_name}")
      path.join(temp_name)
    end

    def git_clone_by_commit(path, temp_name)
      LgPodPlugin.log_blue "git clone #{self.git}"
      Git.init(temp_name)
      FileUtils.chdir(temp_name)
      system("git remote add origin #{self.git}")
      system("git fetch origin #{self.commit}")
      system("git reset --hard FETCH_HEAD")
      path.join(temp_name)
    end

    # clone 代码仓库
    def git_clone_repository(path)
      FileUtils.chdir(path)
      temp_name = "lg_temp_pod"
      if self.git && self.tag
        if LUtils.is_use_gitlab_archive_file(self.git)
          return gitlab_download_tag_zip(path, temp_name)
        elsif self.git.include?("https://github.com")
          return github_download_tag_zip path, temp_name
        else
          return self.git_clone_by_tag(path, temp_name)
        end
      elsif self.git && self.branch
        if LUtils.is_use_gitlab_archive_file(self.git)
          return self.gitlab_download_branch_zip(path, temp_name)
        elsif self.git.include?("https://github.com")
          return self.github_download_branch_zip path, temp_name
        else
          return self.git_clone_by_branch(path, temp_name)
        end
      elsif self.git && self.commit
        if LUtils.is_use_gitlab_archive_file(self.git)
          return self.gitlab_download_commit_zip(path, temp_name)
        elsif self.git.include?("https://github.com")
          return self.github_download_commit_zip path, temp_name
        else
          return self.git_clone_by_commit(path, temp_name)
        end
      elsif self.git
        if LUtils.is_use_gitlab_archive_file(self.git)
          return self.gitlab_download_branch_zip(path, temp_name)
        elsif self.git.include?("https://github.com")
          return self.github_download_branch_zip path, temp_name
        else
          return self.git_clone_by_branch(path, temp_name)
        end
      end

    end

    def pre_download_git_repository
      temp_path = LFileManager.download_director.join("temp")
      if temp_path.exist?
        FileUtils.rm_rf(temp_path)
      end
      lg_pod_path = LRequest.shared.cache.cache_root
      unless lg_pod_path.exist?
        lg_pod_path.mkdir(0700)
      end
      get_temp_folder = git_clone_repository(lg_pod_path)
      #下载 git 仓库失败
      unless get_temp_folder.exist?
        return nil
      end
      if LRequest.shared.single_git
        LgPodPlugin::LCache.cache_pod(self.name, get_temp_folder, { :git => self.git })
      end
      LgPodPlugin::LCache.cache_pod(self.name, get_temp_folder, LRequest.shared.get_cache_key_params)
      FileUtils.chdir(LFileManager.download_director)
      FileUtils.rm_rf(lg_pod_path)
    end

    # 获取最新的一条 commit 信息
    def self.git_ls_remote_refs(git, branch, tag, commit)
      if branch
        LgPodPlugin.log_yellow "git ls-remote #{git} #{branch}"
        result = %x(git ls-remote #{git} #{branch})
        new_commit = result.split(" ").first if result
        return [branch, new_commit]
      elsif tag
        LgPodPlugin.log_yellow "git ls-remote #{git}"
        ls = Git.ls_remote(git, :head => true)
        map = ls["tags"]
        keys = map.keys
        idx = keys.index("#{tag}")
        unless idx
          return [nil, nil]
        end
        key = keys[idx]
        new_commit = map[key][:sha]
        return [nil, new_commit]
      else
        if commit
          return nil, commit
        else
          LgPodPlugin.log_yellow "git ls-remote #{git}"
          ls = Git.ls_remote(git, :head => true)
          find_commit = ls["head"][:sha]
          ls["branches"].each do |key, value|
            sha = value[:sha]
            next if sha != find_commit
            return [key, find_commit]
          end
          return nil, find_commit
        end
      end

    end

  end
end
