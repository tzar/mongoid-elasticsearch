require 'elasticsearch'
require 'mongoid/elasticsearch/version'

require 'active_support/concern'

require 'mongoid/elasticsearch/utils'
require 'mongoid/elasticsearch/es'
require 'mongoid/elasticsearch/callbacks'
require 'mongoid/elasticsearch/index'
require 'mongoid/elasticsearch/indexing'
require 'mongoid/elasticsearch/response'

require 'mongoid/elasticsearch/monkeypatches'

module Mongoid
  module Elasticsearch
    mattr_accessor :autocreate_indexes
    self.autocreate_indexes = true
    
    mattr_accessor :prefix
    self.prefix = ''

    mattr_accessor :client_options
    self.client_options = {}

    mattr_accessor :registered_indexes
    self.registered_indexes = []
    
    mattr_accessor :registered_models
    self.registered_models = []

    extend ActiveSupport::Concern
    included do
      def self.es
        @__es__ ||= Mongoid::Elasticsearch::Es.new(self)
      end

      # Add elasticsearch to the model
      # @option index_name [String] name of the index for this model
      # @option index_options [Hash] Index options to be passed to Elasticsearch
      # when creating an index
      # @option client_options [Hash] Options for Elasticsearch::Client.new
      # @option wrapper [Symbol] Select what wrapper to use for results
      # possible options:
      # :model - creates a new model instance, set its attributes, and marks it as persisted
      # :mash - Hashie::Mash for object-like access  (perfect for simple models, needs gem 'hashie')
      # :none - raw hash
      # :load - load models from Mongo by IDs
      def self.elasticsearch!(options = {})
        options = {
          prefix_name: true,
          index_name: nil,
          client_options: {},
          index_options: {},
          index_mappings: nil,
          wrapper: :model,
          callbacks: true,
          skip_create: false
        }.merge(options)
        
        if options[:wrapper] == :model
          attr_accessor :_type, :_score, :_source
        end

        cattr_accessor :es_client_options, :es_index_name, :es_index_options, :es_wrapper, :es_skip_create, :es_children, :es_type

        self.es_client_options = Mongoid::Elasticsearch.client_options.dup.merge(options[:client_options])
        self.es_index_name     = (options[:prefix_name] ? Mongoid::Elasticsearch.prefix : '') + (options[:index_name] || model_name.plural)
        self.es_index_options  = options[:index_options]
        self.es_wrapper        = options[:wrapper]
        self.es_skip_create    = options[:skip_create]
        self.es_children       = []
        self.es_type           = es.index.type

        Mongoid::Elasticsearch.registered_indexes.push self.es_index_name
        Mongoid::Elasticsearch.registered_indexes.uniq!
        
        Mongoid::Elasticsearch.registered_models.push self.name
        Mongoid::Elasticsearch.registered_models.uniq!
        
        unless options[:index_mappings].nil?
          self.es_index_options = self.es_index_options.deep_merge({
            :mappings => {
              es.index.type.to_sym => {
                :properties => options[:index_mappings]
              }
            }
          })
        end

        include Indexing
        include Callbacks if options[:callbacks]
      end

      def self.elasticsearch_child!(options = {})
        raise "Need to be mapped :to a parent class!" unless options[:to] && options[:to].es

        options = {
          mapping:   {},
          parent:    :parent_id,
          callbacks: true
        }.merge(options)

        @__es__ = options[:to].es
        options[:to].es_children << self

        meta = class << self; self; end
        [:es_client_options, :es_index_name, :es_index_options, :es_wrapper, :es_skip_create].each do |attr|
          meta.send :define_method, attr do
            options[:to].send(attr)
          end
          define_method attr do
            options[:to].send(attr)
          end
        end
        cattr_accessor :child_es, :es_mapping, :es_type
        self.child_es   = Mongoid::Elasticsearch::Es.new(self)
        self.es_mapping = options[:mapping]
        self.es_type    = self.child_es.index.type

        es_mapping["_parent"]                = { "type" => options[:parent_type] || es.index.type }
        es_index_options[:mappings][es_type] = es_mapping

        include Indexing

        define_method :es_parent_id do
          send(options[:parent]).tap do |parent_id|
            raise "Parent/Child relationship needs a parent!" unless parent_id
          end.to_s
        end

        include Callbacks if options[:callbacks]
      end
    end

    def self.create_all_indexes!
      # puts "creating ES indexes"
      Mongoid::Elasticsearch.registered_models.each do |model_name|
        model = model_name.constantize
        model.es.index.create unless model.es_skip_create
      end
    end

    # search multiple models
    def self.search(query, options = {})
      if query.is_a?(String)
        query = {q: Utils.clean(query)}
      end
      # use `_all` or empty string to perform the operation on all indices
      # regardless whether they are managed by Mongoid::Elasticsearch or not
      unless query.key?(:index)
        query.merge!(index: Mongoid::Elasticsearch.registered_indexes.join(','), ignore_indices: 'missing', ignore_unavailable: true)
      end

      page = options[:page]
      per_page = options[:per_page]

      query[:size] = ( per_page.to_i ) if per_page
      query[:from] = ( page.to_i <= 1 ? 0 : (per_page.to_i * (page.to_i-1)) ) if page && per_page

      options[:wrapper] ||= :model

      client = ::Elasticsearch::Client.new Mongoid::Elasticsearch.client_options.dup
      Response.new(client, query, true, nil, options)
    end
  end
end

if defined? Rails
  require 'mongoid/elasticsearch/railtie'
end
