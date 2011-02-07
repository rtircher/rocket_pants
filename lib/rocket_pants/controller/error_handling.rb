module RocketPants
  # Makes it easier to both throw named exceptions (corresponding to
  # error states in the response) and to then process the response into
  # something useable in the response.
  module ErrorHandling
    extend ActiveSupport::Concern

    included do
      rescue_from RocketPants::Error, :with => :render_error
      class_inheritable_accessor :error_mapping
      self.error_mapping = {}
    end
    
    module ClassMethods

      def map_error!(from, to)
        error_mapping[from] = to
        rescue_from from, :with => :render_error
      end

    end

    module InstanceMethods
      
      # Dynamically looks up and then throws the error given by a symbolic name.
      # Optionally takes a string message argument and a hash of 'context'.
      # @overload error!(name, context = {})
      #   @param [Symbol] name the name of the exception, looked up using RocketPants::Errors
      #   @param [Hash{Symbol => Object}] context the options passed to the error message translation.
      # @overload error!(name, message, context = {})
      #   @param [Symbol] name the name of the exception, looked up using RocketPants::Errors
      #   @param [String] message an optional message describing the error
      #   @param [Hash{Symbol => Object}] context the options passed to the error message translation.
      # @raise [RocketPants::Error] the error from the given options
      def error!(name, *args)
        context   = args.extract_options!
        klass     = Errors[name] || Error
        exception = klass.new(*args).tap { |e| e.context = context }
        raise exception
      end
      
      # From a given exception, gets the corresponding error message using I18n.
      # It will use context (if defined) on the exception for the I18n context base and
      # will use either the result of Error#error_name (if present) or :system for
      # the name of the error.
      # @param [StandardError] exception the exception to get the message from
      # @return [String] the found error message.
      def lookup_error_message(exception)
        # TODO: Add in notification hooks for non-standard exceptions.
        name    = lookup_error_name(exception)
        message = (exception.message == exception.class.name) ? 'An unknown error has occurred.' : exception.message
        I18n.t name, lookup_error_context(exception).reverse_merge(:scope => :"rocket_pants.errors", :default => message)
      end

      # Lookup error name will automatically handle translating errors to a
      # simpler, symbol representation. It's implemented like this to make it
      # possible to override to a simple format.
      # @param [StandardError] exception the exception to find the name for
      # @return [Symbol] the name of the given error
      def lookup_error_name(exception)
        if exception.respond_to?(:error_name)
          exception.error_name
        else
          :system
        end
      end

      # Returns the error status code for a given exception.
      # @param [StandardError] exception the exception to find the status for
      # @return [Symbol] the name of the given error
      def lookup_error_status(exception)
        exception.respond_to?(:http_status) ? exception.http_status : 500
      end

      # Returns the i18n context for a given exception.
      # @param [StandardError] exception the exception to find the context for
      # @param [Hash] the i18n translation context.
      def lookup_error_context(exception)
        exception.respond_to?(:context) ? exception.context : {}
      end
      
      # Returns extra error details for a given object, making it useable
      # for hooking in external exceptions.
      def lookup_error_extras(exception)
        {}
      end

      # Renders an exception as JSON using a nicer version of the error name and
      # error message, following the typically error standard as laid out in the JSON
      # api design.
      # @param [StandardError] exception the error to render a response for.
      def render_error(exception)
        logger.debug "Rendering error for #{exception.class.name}: #{exception.message}" if logger
        # When a normalised class is present, make sure we
        # convert it to a useable error class.
        if (normalised_class = error_mapping[exception.class])
          exception = normalised_class.new(exception.message)
        end
        self.status = lookup_error_status(exception)
        render_json({
          :error             => lookup_error_name(exception).to_s,
          :error_description => lookup_error_message(exception)
        }.merge(lookup_error_extras(exception)))
      end
      
    end
    
  end
end