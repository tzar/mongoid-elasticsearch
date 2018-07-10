class Article
  include Mongoid::Document
  include Mongoid::Timestamps::Short
  #include ActiveModel::ForbiddenAttributesProtection

  field :name

  include Mongoid::Slug
  slug :name

  field :tags

  include Mongoid::Elasticsearch
  i_fields = {
    name:     {type: 'string', analyzer: 'snowball'},
    raw:      {type: 'string', index: :not_analyzed}
  }

  elasticsearch! index_name: 'mongoid_es_news', prefix_name: false, index_mappings: {
    name: {
      type: 'multi_field',
      fields: i_fields
    },
    _slugs:   {type: 'string', index: :not_analyzed},
    tags: {type: 'string', include_in_all: false}
  }, wrapper: :load
end

