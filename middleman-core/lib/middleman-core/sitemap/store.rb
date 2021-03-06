# Used for merging results of metadata callbacks
require "active_support/core_ext/hash/deep_merge"

# Sitemap namespace
module Middleman::Sitemap
  
  # The Store class
  #
  # The Store manages a collection of Resource objects, which represent
  # individual items in the sitemap. Resources are indexed by "source path",
  # which is the path relative to the source directory, minus any template
  # extensions. All "path" parameters used in this class are source paths.
  class Store
    
    # @return [Middleman::Application]
    attr_accessor :app
    
    # Initialize with parent app
    # @param [Middleman::Application] app
    def initialize(app)
      @app   = app
      @resources = []
      
      @_lookup_cache = { :path => {}, :destination_path => {} }
      @resource_list_manipulators = []
      
      # Register classes which can manipulate the main site map list
      register_resource_list_manipulator(:on_disk, Middleman::Sitemap::Extensions::OnDisk.new(self),  false)
      
      # Proxies
      register_resource_list_manipulator(:proxies, @app.proxy_manager, false)
      
      # Ignores
      register_resource_list_manipulator(:ignores, @app.ignore_manager, false)
      
      rebuild_resource_list!(:after_base_init)
    end

    # Register a klass which can manipulate the main site map list
    # @param [Class] klass
    # @param [Boolean] immediately_rebuild
    # @return [void]
    def register_resource_list_manipulator(name, inst, immediately_rebuild=true)
      @resource_list_manipulators << [name, inst]
      rebuild_resource_list!(:registered_new) if immediately_rebuild
    end
    
    # Rebuild the list of resources from scratch, using registed manipulators
    # @return [void]
    def rebuild_resource_list!(reason=nil)
      @resources = @resource_list_manipulators.inject([]) do |result, (_, inst)|
        inst.manipulate_resource_list(result)
      end
      
      # Reset lookup cache
      cache_structure = { :path => {}, :destination_path => {} }
      @_lookup_cache = @resources.inject(cache_structure) do |cache, resource|
        cache[:path][resource.path] = resource
        cache[:destination_path][resource.destination_path] = resource
        cache
      end
    end
    
    # Find a resource given its original path
    # @param [String] request_path The original path of a resource.
    # @return [Middleman::Sitemap::Resource]
    def find_resource_by_path(request_path)
      request_path = ::Middleman::Util.normalize_path(request_path)
      @_lookup_cache[:path][request_path]
    end
    
    # Find a resource given its destination path
    # @param [String] request_path The destination (output) path of a resource.
    # @return [Middleman::Sitemap::Resource]
    def find_resource_by_destination_path(request_path)
      request_path = ::Middleman::Util.normalize_path(request_path)
      @_lookup_cache[:destination_path][request_path]
    end
    
    # Get the array of all resources
    # @param [Boolean] include_ignored Whether to include ignored resources
    # @return [Array<Middleman::Sitemap::Resource>]
    def resources(include_ignored=false)
      if include_ignored
        @resources
      else
        @resources.reject(&:ignored?)
      end
    end
    
    # Register a handler to provide metadata on a file path
    # @param [Regexp] matcher
    # @return [Array<Array<Proc, Regexp>>]
    def provides_metadata(matcher=nil, &block)
      @_provides_metadata ||= []
      @_provides_metadata << [block, matcher] if block_given?
      @_provides_metadata
    end
    
    # Get the metadata for a specific file
    # @param [String] source_file
    # @return [Hash]
    def metadata_for_file(source_file)
      blank_metadata = { :options => {}, :locals => {}, :page => {}, :blocks => [] }
      
      provides_metadata.inject(blank_metadata) do |result, (callback, matcher)|
        next result if !matcher.nil? && !source_file.match(matcher)
        
        metadata = callback.call(source_file)
        result.deep_merge(metadata)
      end
    end
    
    # Register a handler to provide metadata on a url path
    # @param [Regexp] matcher
    # @return [Array<Array<Proc, Regexp>>]
    def provides_metadata_for_path(matcher=nil, &block)
      @_provides_metadata_for_path ||= []
      @_provides_metadata_for_path << [block, matcher] if block_given?
      @_provides_metadata_for_path
    end
    
    # Get the metadata for a specific URL
    # @param [String] request_path
    # @return [Hash]
    def metadata_for_path(request_path)
      blank_metadata = { :options => {}, :locals => {}, :page => {}, :blocks => [] }
      
      provides_metadata_for_path.inject(blank_metadata) do |result, (callback, matcher)|
        case matcher
        when Regexp
          next result unless request_path.match(matcher)
        when String
          next result unless File.fnmatch("/" + matcher.sub(%r{^/}, ''), "/#{request_path}")
        end
        
        metadata = callback.call(request_path)
        
        if metadata.has_key?(:blocks)
          result[:blocks] << metadata[:blocks]
          metadata.delete(:blocks)
        end

        result.deep_merge(metadata)
      end
    end
  end
end