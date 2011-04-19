module Noodall
  class FormResponse
    include MongoMapper::EmbeddedDocument

    key :name, String
    key :email, String, :format => /.+\@.+\..+/
    key :ip, String, :required => true
    key :referrer, String, :required => true
    key :created_at, Time, :required => true
    key :approved, Boolean, :default => true
    key :defensio_signature, String
    key :spaminess, Float, :default => 0

    def required_fields
      self.form.fields.select{ |f| f.required? }
    end

    before_save :check_for_spam
    attr_protected :approved

    embedded_in :form

    def approve!
      self.approved = true
      self.save!
      self.class.defensio.put_document(defensio_signature, { :allow => true })
    end

    def mark_as_spam!
      self.approved = false
      self.save!
      self.class.defensio.put_document(defensio_signature, { :allow => false })
    end

    def is_spam?
      self.approved == false
    end

    def string_value(name)
      return '' unless self.respond_to?(name)
      value = self.send(name)

      if value.is_a?(Array)
        "[#{value.join(', ')}]"
      else
        "Val: #{value}"
      end
    end

  protected
    def check_for_spam
      if self.defensio_signature.blank?
        status, response = self.class.defensio.post_document(self.defensio_attributes)
        return unless status == 200

        self.defensio_signature = response['signature']
        self.spaminess = response['spaminess']
        self.approved = response['allow']
      end
    end

    def self.defensio
      @@defensio ||= Defensio.new(self.defensio_api_key)
    end

    def self.defensio_api_key
      defensio_config['api_key']
    end

    def self.defensio_config
      logger.info "No Defensio config found" unless FileTest.exists?(File.join(Rails.root, 'config', 'defensio.yml'))
      @defensio_config ||= YAML::load(File.open(File.join(Rails.root, 'config', 'defensio.yml')))
    end

    def defensio_attributes
      {
        'client' => 'Noodall Form Builder | 1.0 | Beef Ltd | hello@wearebeef.co.uk ',
        'type' => 'other',
        'platform' => 'noodall',
        'content' => self.form.fields.map{|f| "#{f.name}: #{self.send(f.underscored_name) if self.respond_to?(f.underscored_name)}" }.join(' '),
        'author-email' => self.email,
        'author-name' => self.name,
        'author-ip' => self.ip
      }
    end


  private
    validate :custom_validation

    def custom_validation
      return if required_fields.nil? || !self.new_record?
      required_fields.each do |field|
        self.add_error(field.underscored_name.to_sym, "can't be empty") if self.send(field.underscored_name).blank?
      end
    end
  end
end
