module Ironfan
  class Dsl
    class Cluster < Ironfan::Dsl::Compute
      include Ironfan::Plugin::Base; register_with Ironfan::Dsl::Realm

      collection :facets, Ironfan::Dsl::Facet, resolver: :deep_resolve

      def self.plugin_hook(owner, attrs, plugin_name, full_name, &blk)
        owner.cluster(plugin_name, new(attrs.merge(name: full_name, owner: owner)))
        _project(cluster, &blk)
      end

      def self.definitions
        @clusters ||= {}
      end

      def self.define(attrs = {}, &blk)
        cl = new(attrs)
        cl.receive!({}, &blk) # the ordering of the initialize method is super fragile
        definitions[attrs[:name].to_sym] = cl
      end
      
      def initialize(attrs = {}, &blk)
        super
        self.realm_name    attrs[:owner].name          unless attrs[:owner].nil?
        self.cluster_names attrs[:owner].cluster_names unless attrs[:owner].nil?
        self.cluster_role  Ironfan::Dsl::Role.new(name: Compute.cluster_role_name(realm_name, cluster_name))
      end

      def resolve
        self.class.definitions[name.to_sym] = super
      end

      # Utility method to reference all servers from constituent facets
      def servers
        result = Gorillib::ModelCollection.new(item_type: Ironfan::Dsl::Server, key_method: :full_name)
        facets.each{ |f| f.servers.each{ |s| result << s } }
        result
      end

      def children
        facets.to_a + components.to_a
      end

      def cluster_name
        name
      end

      def full_cluster_name
        full_name
      end

      def full_name
        "#{realm_name}-#{name}"
      end
    end
  end
end
