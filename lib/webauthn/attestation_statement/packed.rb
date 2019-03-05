# frozen_string_literal: true

require "openssl"
require "webauthn/attestation_statement/base"

module WebAuthn
  # Implements https://www.w3.org/TR/2018/CR-webauthn-20180807/#packed-attestation
  # ECDAA attestation is unsupported.
  module AttestationStatement
    class Packed < Base
      # Follows "Verification procedure"
      def valid?(authenticator_data, client_data_hash)
        check_unsupported_feature

        valid_format? &&
          valid_certificate_chain?(authenticator_data.credential) &&
          meet_certificate_requirement? &&
          valid_signature?(authenticator_data, client_data_hash) &&
          attestation_type_and_trust_path
      end

      private

      def valid_format?
        algorithm && signature && (
          [raw_attestation_certificates, raw_ecdaa_key_id].compact.size < 2
        )
      end

      def check_unsupported_feature
        if raw_ecdaa_key_id
          raise NotSupportedError, "ecdaaKeyId of the packed attestation format is not implemented yet"
        end
      end

      def attestation_certificate_chain
        @attestation_certificate_chain ||= raw_attestation_certificates&.map do |cert|
          OpenSSL::X509::Certificate.new(cert)
        end
      end

      def attestation_certificate
        attestation_certificate_chain&.first
      end

      def valid_certificate_chain?(credential)
        public_keys = attestation_certificate_chain&.map(&:public_key) || [credential.public_key_object]
        public_keys.all? do |public_key|
          public_key.is_a?(OpenSSL::PKey::EC) && public_key.check_key
        end
      end

      # Check https://www.w3.org/TR/2018/CR-webauthn-20180807/#packed-attestation-cert-requirements
      def meet_certificate_requirement?
        if attestation_certificate
          subject = attestation_certificate.subject.to_a

          attestation_certificate.version == 2 &&
            subject.assoc('OU')&.at(1) == "Authenticator Attestation" &&
            attestation_certificate.extensions.find { |ext| ext.oid == 'basicConstraints' }&.value == 'CA:FALSE'
        else
          true
        end
      end

      def valid_signature?(authenticator_data, client_data_hash)
        (attestation_certificate&.public_key || authenticator_data.credential.public_key_object).verify(
          "SHA256",
          signature,
          verification_data(authenticator_data, client_data_hash)
        )
      end

      def verification_data(authenticator_data, client_data_hash)
        authenticator_data.data + client_data_hash
      end

      def attestation_type_and_trust_path
        if raw_attestation_certificates&.any?
          [WebAuthn::AttestationStatement::ATTESTATION_TYPE_BASIC_OR_ATTCA, attestation_certificate_chain]
        else
          [WebAuthn::AttestationStatement::ATTESTATION_TYPE_SELF, nil]
        end
      end
    end
  end
end
