# Copyright 2011-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'multi_json'

module Aws
  class ClientFactory

    class NoSuchApiVersionError < RuntimeError; end

    class << self

      # Constructs and returns versioned API client.  Defaults to the 
      # newest/latest API version.
      #
      #     Aws::DynamoDB::Client.new
      #     #=> #<Aws::DynamoDB::Client::V20120810>
      #
      # ## Specify API Version
      #
      # You can specify the API version and get a different client.
      #
      #     Aws::DynamoDB::Client.new(api_version: '2011-12-05')
      #     #=> #<Aws::DynamoDB::Client::V20111205>
      #
      # ## Locking API Versions
      #
      # You can lock the API version for a service via {Aws.config}:
      #
      #     Aws.config[:dynamodb] = { api_version: '2011-12-05' }
      #     Aws::DynamoDB::Client.new
      #     #=> #<Aws::DynamoDB::Client::V20111205>
      #
      # @return [Seahorse::Client::Base] Returns a versioned client.
      #
      # @see .versions
      # @see .latest_version
      # @see .default_version
      #
      def new(options = {})
        client_class(options).new(client_defaults.merge(options))
      end

      # Registers a new API version for this client factory.  You need to
      # provide the API version in `YYYY-MM-DD` format and an API.
      # The `api` may be a string path to an API on disk or a fully
      # constructed `Seahorse::Model::Api` object.
      #
      # @example Register a client with a path to the JSON api.
      #   Aws::S3::Client.add_version('2013-01-02', '/path/to/api/src.json')
      #
      # @example Register a client with a hydrated API.
      #   api = Seahorse::Model::Api.from_hash(api_src)
      #   Aws::S3::Client.add_version('2013-01-02', api)
      #
      # @param [String<YYYY-MM-DD>] api_version
      # @param [String<Pathname>, Seahorse::Model::Api] api
      # @return [void]
      def add_version(api_version, api)
        apis[api_version] = api
      end

      # @return [Array<String>] Returns a list of supported API versions
      #   in a `YYYY-MM-DD` format.
      def versions
        apis.keys.sort
      end

      # @return [String<YYYY-MM-DD>] Returns the most current API version.
      def latest_version
        versions.last
      end

      # @return [String<YYYY-MM-DD>] Returns the default API version.  This
      #   is the version of the client that will be constructed if there
      #   is other configured or specified API version.
      def default_version
        client_defaults[:api_version] || latest_version
      end

      # @return [Array<Class>] Returns all of the registered versioned client
      #   classes for this factory.
      def client_classes
        versions.map { |v| client_class(api_version: v) }
      end

      # Adds a plugin to each versioned client class.
      # @param [Plugin] plugin
      # @return [void]
      def add_plugin(plugin)
        client_classes.each do |client_class|
          client_class.add_plugin(plugin)
        end
      end

      # Removes a plugin from each versioned client class.
      # @param [Plugin] plugin
      # @return [void]
      def remove_plugin(plugin)
        client_classes.each do |client_class|
          client_class.remove_plugin(plugin)
        end
      end

      # @return [Symbol]
      # @api private
      attr_accessor :identifier

      # @param [Symbol] identifier The downcased short name for this service.
      # @param [Array<Api, String>] apis An array of client APIs for this
      #   service.  Values may be string paths to API files or instances of
      #   `Seahorse::Model::Api`.
      # @return [Class<ClientFactory>]
      # @api private
      def define(identifier, apis = [])
        klass = Class.new(self)
        klass.identifier = identifier.to_sym
        apis.each do |api|
          if api.is_a?(String)
            yyyy_mm_dd = api.match(/\d{4}-\d{2}-\d{2}/)[0]
            klass.add_version(yyyy_mm_dd, api)
          else
            klass.add_version(api.version, api)
          end
        end
        klass
      end

      private

      def client_defaults
        Aws.config[identifier] || {}
      end

      def client_class(options)
        version = options[:api_version] || default_version
        const_get("V#{version.gsub('-', '')}")
      end

      def apis
        @apis ||= {}
      end

      def const_missing(constant)
        if constant =~ /^V\d{8}$/
          api = api_for(constant)
          const_set(constant, Seahorse::Client.define(api: api))
        else
          super
        end
      end

      def api_for(constant)
        api_version = version_for(constant)
        api = apis[api_version]
        case api
        when Seahorse::Model::Api then api
        when String then load_api(api)
        else
          msg = "API #{api_version} not defined for #{name}"
          raise NoSuchApiVersionError, msg
        end
      end

      def version_for(constant)
        yyyy = constant[1,4]
        mm = constant[5,2]
        dd = constant[7,2]
        [yyyy, mm, dd].join('-')
      end

      def load_api(path)
        api = MultiJson.load(File.read(path))
        if api.key?('metadata')
          Seahorse::Model::Api.from_hash(api)
        else
          ApiTranslator.translate(api)
        end
      end

    end
  end
end