module Ironfan
  class Provider

    class ChefServer < Ironfan::Provider
      field :types,     Array,  :default => [ :nodes, :clients ]
      field :sync,      Array,  :default => [ :roles, :nodes ]

      collection :clients,      Ironfan::Provider::ChefServer::Client
      collection :nodes,        Ironfan::Provider::ChefServer::Node
      collection :roles,        Ironfan::Provider::ChefServer::Role

      def initialize
        super
        @clients        = Ironfan::Provider::ChefServer::Clients.new
        @nodes          = Ironfan::Provider::ChefServer::Nodes.new
        @roles          = Ironfan::Provider::ChefServer::Roles.new
      end

      def create_dependencies!(machines)
        delegate_to clients, :create! => machines
      end

      def create_instances!(machines)
        delegate_to nodes, :create! => machines
      end

      def save!(machines)
        delegate_to [nodes, roles], :save! => machines
      end

      def load!(machines)
        delegate_to [nodes, clients], :load! => machines
      end

      def correlate!(machines)
        delegate_to [nodes, clients], :load! => machines
      end

      def validate!(machines)
        delegate_to clients, :load! => machines
      end

    end

  end
end