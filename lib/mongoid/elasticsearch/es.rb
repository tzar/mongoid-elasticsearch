module Mongoid
  module Elasticsearch
    class Es
      INDEX_STEP = 100
      attr_reader :klass, :version

      def initialize(klass)
        @klass = klass
        @version = Gem::Version.new(client.info['version']['number'])
      end

      def client
        # dup is needed because Elasticsearch::Client.new changes options hash inplace
        @client ||= ::Elasticsearch::Client.new klass.es_client_options.dup
      end

      def index
        @index ||= Index.new(self)
      end

      def index_all(step_size = INDEX_STEP)
        index.reset
        q = klass.asc(:id)
        steps = (q.count / step_size) + 1
        last_id = nil
        steps.times do |step|
          if last_id
            docs = q.gt(id: last_id).limit(step_size).to_a
          else
            docs = q.limit(step_size).to_a
          end
          last_id = docs.last.try(:id)

          bulk_index(docs)
          if block_given?
            yield steps, step, docs
          end
        end       
      end
      def bulk_index(docs)
        docs = docs.map do |obj|
          if obj.es_index?
            {
              index: {
                data: obj.as_indexed_json
              }.merge(bulk_options_for(obj))
            }
          else
            nil
          end
        end.compact
        return if docs.empty?
        client.bulk({body: docs})
      end

      def search(query, options = {})
        if query.is_a?(String)
          query = {q: Utils.clean(query)}
        end

        page = options[:page]
        per_page = options[:per_page].nil? ? options[:per] : options[:per_page]

        query[:size] = ( per_page.to_i ) if per_page
        query[:from] = ( page.to_i <= 1 ? 0 : (per_page.to_i * (page.to_i-1)) ) if page && per_page

        options[:wrapper] ||= klass.es_wrapper

        Response.new(client, query.merge(custom_type_options(options)), true, klass, options)
      end

      def all(options = {})
        search({body: {query: {match_all: {}}}}, options)
      end

      def bulk_options_for(obj)
        options = type_options(obj)
        {
          _id:    obj.id.to_s,
          _type:  options[:type],
          _index: options[:index]
        }.merge(parent_options(obj))
      end
      def options_for(obj)
        {id: obj.id.to_s}.merge(type_options(obj)).merge(parent_options(obj))
      end

      def parent_options(obj)
        if parent_id = obj.es_parent_id
          {parent: parent_id.to_s}
        else
          {}
        end
      end

      def custom_type_options(options)
        if !options[:include_type].nil? && options[:include_type] == false
          {index: index.name}
        else
          type_options
        end
      end

      def type_options(obj = nil)
        {index: index.name, type: obj ? obj.es_type : index.type}
      end

      def index_item(obj)
        client.index({body: obj.as_indexed_json}.merge(options_for(obj)))
      end

      def remove_item(obj)
        client.delete(options_for(obj).merge(ignore: 404))
      end

      def completion_supported?
        @version > Gem::Version.new('0.90.2')
      end

      def completion(text, field = "suggest")
        raise "Completion not supported in ES #{@version}" unless completion_supported?
        body = {
          q: {
            text: Utils.clean(text),
            completion: {
              field: field
            }
          }
        }
        results = client.suggest(index: index.name, body: body)
        results['q'][0]['options']
      end
    end
  end
end
