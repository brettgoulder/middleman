module Middleman::Sitemap::Extensions
  
  module Ignores
    
    # Setup extension
    class << self
    
      # Once registered
      def registered(app)
        # Include methods
        app.send :include, InstanceMethods
        
        ::Middleman::Sitemap::Resource.send :include, ResourceInstanceMethods
      end
    
      alias :included :registered
    end
    
    module ResourceInstanceMethods
      def ignored?
        @app.ignore_manager.ignored?(path) || 
        (!proxy? &&
          @app.ignore_manager.ignored?(source_file.sub("#{@app.source_dir}/", ""))
        )
      end
    end
    
    module InstanceMethods
      def ignore_manager
        @_ignore_manager ||= IgnoreManager.new(self)
      end
      
      def ignore(*args, &block)
        ignore_manager.ignore(*args, &block)
      end
    end
    
    class IgnoreManager
      def initialize(app)
        @app = app

        @ignored_callbacks = []
      end
      
      # Ignore a path or add an ignore callback
      # @param [String, Regexp] path, path glob expression, or path regex
      # @return [void]
      def ignore(path=nil, &block)
        if path.is_a? Regexp
          @ignored_callbacks << Proc.new {|p| p =~ path }
        elsif path.is_a? String
          path_clean = ::Middleman::Util.normalize_path(path)
          if path_clean.include?("*") # It's a glob
            @ignored_callbacks << Proc.new {|p| File.fnmatch(path_clean, p) }
          else
            @ignored_callbacks << Proc.new {|p| p == path_clean }
          end
        elsif block_given?
          @ignored_callbacks << block
        end

        @app.sitemap.rebuild_resource_list!(:added_ignore_rule)
      end

      # Whether a path is ignored
      # @param [String] path
      # @return [Boolean]
      def ignored?(path)
        path_clean = ::Middleman::Util.normalize_path(path)
        @ignored_callbacks.any? { |b| b.call(path_clean) }
      end

      # Update the main sitemap resource list
      # @return [void]
      def manipulate_resource_list(resources)
        # No op
        resources
      end
    end
  end
end