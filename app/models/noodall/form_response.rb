# encoding: utf-8
require 'spam/defensio_spam_checker'
require 'spam/akismet_spam_checker'

module Noodall
  class FormResponse
    include MongoMapper::Document

    key :name, String, :required => true
    key :email, String, :format => /^[-a-z0-9_+\.]+\@([-a-z0-9]+\.)+[a-z0-9]{2,4}$/i
    key :ip, String, :required => true
    key :referrer, String, :required => true
    key :created_at, Time, :required => true
    key :approved, Boolean, :default => false
    key :checked, Boolean, :default => false

    key :started_at, String
    key :filtering_out, String

    # For Defensio only
    key :defensio_signature, String

    before_save :check_for_spam

    attr_protected :approved

    timestamps!

    belongs_to :form, :class => Noodall::Form, :foreign_key => 'noodall_form_id'

    validate :is_not_a_spam, on: :create

    def self.model_name
      ActiveModel::Name.new(self, nil, "Response")
    end

    # Overriden to set up keys after find
    def initialize_from_database(attrs={})
      super.tap do
        set_up_keys!
      end
    end

    def approve!
      self.approved = true
      self.save!
      self.class.spam_checker.mark_as_ham!(self)
    end

    def mark_as_spam!
      self.approved = false
      self.save!
      self.class.spam_checker.mark_as_spam!(self)
    end

    def is_spam?
      self.approved == false
    end

    # Create appropriate MongoMapper keys for current instance
    # based on the fields of the form it belongs to
    def set_up_keys!
      return unless form

      form.fields.each do |f|
        next if self.keys.include?(f.underscored_name)

        self.class.send(:key, f.underscored_name, f.keys['default'].type, :required => f.required, :default => f.default)
      end
    end

    # Merge meta keys with real keys
    def keys
      super.merge( class_eval( 'keys' ) )
    end


    def is_not_a_spam
      errors.add(:base, 'Sorry your response could not be saved') if filtering_out.present?
      if started_at.present?
        # If a something enters a form in less than 10 seconds, there is a good chance it's a bot.
        errors.add(:base, 'Sorry your response could not be saved too fast') if  Time.now - Time.at(started_at.to_i) < 10
      end

      if (/\p{Han}|\p{Katakana}|\p{Hiragana}|\p{Hangul}/.match form_content(self)).present?
        errors.add(:base, 'Sorry some characters are not valid')
      end

      if ip.present?
        errors.add(:base, 'Too many submissions') if Noodall::FormResponse.where(ip: ip, :created_at.gte => Time.now.beginning_of_day).count > 10
      end
    end

    protected


    def form_content(form_response)
      form_response.form.fields.map do |f|
        if form_response.respond_to?(f.underscored_name)
          "#{f.name}: #{form_response.send(f.underscored_name)}"
        end
      end.join(' ')
    end

    def check_for_spam
      return if spam_checked?

      # If no spam checking is enabled, just approve automatically
      if self.class.spam_checker.nil?
        self.approved = true
        return
      end

      begin
        spam, metadata = self.class.spam_checker.check(self)

        self.approved           = spam
        self.defensio_signature = metadata
        self.checked            = true
      rescue Noodall::FormBuilder::SpamCheckerConnectionError => e
        self.approved           = true
        self.defensio_signature = nil
        self.checked            = false

        Exceptional.handle(e, 'Spam Checker API Error') if defined?(Exceptional)
      end

      true
    end

    def spam_checked?
      self.checked
    end

    def self.spam_checker
      @@spam_checker ||= begin

        spam_service = Noodall::FormBuilder.spam_protection
        return if spam_service.nil?

        spam_checker = "#{spam_service.capitalize}SpamChecker"
        klass = Noodall::FormBuilder.const_get(spam_checker)

        klass.new
      end
    end
  end
end
