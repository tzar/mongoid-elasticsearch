module Mongoid
  module Elasticsearch
    module Indexing
      extend ActiveSupport::Concern
      def as_indexed_json
        serializable_hash.reject { |k, v| %w(_id c_at u_at created_at updated_at).include?(k) }
      end
      
      def es_index?
        true
      end

      def es_routing_options
        {}
      end
      def es_parent_id
        # Stub
      end

      def es_update
        if destroyed? || !es_index?
          self.class.es.remove_item(self)
        else
          self.class.es.index_item(self)
        end
      end
    end
  end
end

