module  Noodall
  class Field
    include MongoMapper::EmbeddedDocument
  
    key :_type, String, :required => true
    key :name, String, :required => true
    key :label, String
    key :default, String
    key :required, Boolean, :default => false, :required => true
  
    embedded_in :form
    
    def underscored_name
      name.parameterize('_').to_s
    end
    
    def default_class(response)
      'default-value' if response.send(underscored_name.to_sym) == default
    end
  
    def mandatory?
      Form::MANDATORY_FIELDS.include?(self.name)
    end
  end
end