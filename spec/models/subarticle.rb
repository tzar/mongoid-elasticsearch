class SubArticle
  include Mongoid::Document

  field :name
  field :parent_id

  include Mongoid::Elasticsearch

  elasticsearch_child! to: Article, parent: :parent_id, mapping: {
    properties: {
      name: { type: :string }
    }
  }, wrapper: :load
end

