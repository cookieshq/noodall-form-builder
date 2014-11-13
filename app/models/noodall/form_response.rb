require 'spam/akismet_spam_checker'

module Noodall
  class FormResponse
    include MongoMapper::Document

    key :name, String
    key :email, String, :format => /^[-a-z0-9_+\.]+\@([-a-z0-9]+\.)+[a-z0-9]{2,4}$/i
    key :ip, String, :required => true
    key :referrer, String, :required => true
    key :created_at, Time, :required => true
    key :approved, Boolean, :default => true
    key :checked, Boolean, :default => false
    key :defensio_signature, String
    key :spaminess, Float, :default => 0

    before_save :check_for_spam
    attr_protected :approved

    timestamps!

    belongs_to :form, :class => Noodall::Form, :foreign_key => 'noodall_form_id'

    def required_fields
      self.form.fields.select{ |f| f.required? }
    end

    def correct_fields?
      self.form.fields.each do |f|
        return false unless self.respond_to?(f.name.downcase.parameterize("_").to_sym)
      end
      return true
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

    def string_value(name)
      return '' unless self.respond_to?(name)
      value = self.send(name)

      if value.is_a?(Array)
        value.join(', ')
      else
        value.to_s
      end
    end

  protected

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

  private
    validate :custom_validation

    def custom_validation
      return true if required_fields.nil? || !self.new_record?
      required_fields.each do |field|
        self.errors.add(field.underscored_name.to_sym, "can't be empty") if self.send(field.underscored_name).blank?
      end
      return true if self.errors.empty?
    end
  end
end
