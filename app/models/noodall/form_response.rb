module Noodall
  class FormResponse
    include MongoMapper::Document

    key :name, String, :required => true
    key :email, String, :format => /^[-a-z0-9_+\.]+\@([-a-z0-9]+\.)+[a-z0-9]{2,4}$/i
    key :ip, String, :required => true
    key :referrer, String, :required => true
    key :created_at, Time, :required => true
    key :approved, Boolean, :default => true
    key :defensio_signature, String
    key :spaminess, Float, :default => 0

    before_save :check_for_spam, :if => :defensio_configuired?

    attr_protected :approved


    timestamps!

    belongs_to :form, :class => Noodall::Form, :foreign_key => 'noodall_form_id'

    # Overiden to set up keys after find
    def initialize_from_database(attrs={})
      super.tap do
        set_up_keys!
      end
    end

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

    # Create appropriate MongoMapper keys for current instance
    # based on the fields of the form it belongs to
    def set_up_keys!
      form.fields.each do |f|
        class_eval do
          key f.underscored_name, f.keys['default'].type, :required => f.required, :default => f.default
        end
      end if form
    end

    # Merge meta keys with real keys
    def keys
      super.merge( class_eval( 'keys' ) )
    end

    protected
    def defensio_configuired?
      defined?(Defensio) && !self.class.defensio_config.blank?
    end

    def check_for_spam
      if self.defensio_signature.blank?
        status, response = self.class.defensio.post_document(self.defensio_attributes)
        return true unless status == 200

        self.defensio_signature = response['signature']
        self.spaminess = response['spaminess']
        self.approved = response['allow']
      end
      return true
    end

    def self.defensio
      @@defensio ||= Defensio.new(self.defensio_api_key)
    end

    def self.defensio_api_key
      defensio_config['api_key']
    end

    def self.defensio_config
      begin
        @defensio_config ||= YAML::load(File.open(File.join(Rails.root, 'config', 'defensio.yml')))
      rescue Exception => e
        puts "Failed to load Defensio config: #{e}"
        @defensio_config = {}
      end
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

  end
end
