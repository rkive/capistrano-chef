require 'capistrano'
require 'chef/knife'
require 'chef/data_bag_item'
require 'chef/search/query'

module Capistrano::Chef
  # Set up chef configuration
  def self.configure_chef
    knife = Chef::Knife.new
    # If you don't do this it gets thrown into debug mode
    knife.config = { :verbosity => 1 }
    knife.configure_chef
  end

  # Do a search on the Chef server and return an attary of the requested
  # matching attributes
  def self.search_chef_nodes(query = '*:*', arg = :ipaddress)
    search_proc = \
      case arg
      when Proc
        arg
      when Hash
        iface, family = arg.keys.first.to_s, arg.values.first.to_s
        Proc.new do |n|
          addresses = n["network"]["interfaces"][iface]["addresses"]
          addresses.select{|address, data| data["family"] == family }.keys.first
        end
      when Symbol, String
        Proc.new{|n| n[arg.to_s]}
      else
        raise ArgumentError, 'Search arguments must be Proc, Hash, Symbol, String.'
      end
    Chef::Search::Query.new.search(:node, query)[0].map(&search_proc)
  end

  def self.get_data_bag_item(id, data_bag = :apps)
    Chef::DataBagItem.load(data_bag, id).raw_data
  end

  # Load into Capistrano
  def self.load_into(configuration)
    self.configure_chef
    configuration.set :capistrano_chef, self
    configuration.load do
      def chef_role(name, query = '*:*', options = {})
        if attribute = options.delete(:attribute)
          opts = (capistrano_chef.search_chef_nodes(query, attribute) + [options])
        else
          opts = (capistrano_chef.search_chef_nodes(query) + [options])
        end
        role name, *opts
      end

      def list_servers(query)
        migrator = Chef::Search::Query.new.search(:node, query).first.sort {|a,b| a['roles'] <=> b['roles'] }.each{ |node|
          next unless node['cloud']
          printf("%-25s %-25s %-30s\n", node['cloud']['public_ips'], node['cloud']['local_hostname'], node['roles'])
        }
      end

      def migrator_role(query, options={})
        migrator = Chef::Search::Query.new.search(:node, query).first.map{ |node|
          node['cloud']['public_ips']
        }.flatten.first
        role :db, migrator, { primary => true }.merge(options) 
      end

      def set_authentication(opts)
        Chef::Config.merge!(opts)
      end

      def set_from_data_bag(data_bag = :apps)
        raise ':application must be set' if fetch(:application).nil?
        capistrano_chef.get_data_bag_item(application, data_bag).each do |k, v|
          set k, v
        end
      end
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Chef.load_into(Capistrano::Configuration.instance)
end
