/**
 * @description Test/mock implementation of StripeCustomerGateway.IStripeCustomerGateway.
 * Returns deterministic Stripe customer ids, and can simulate failures by name.
 */
@IsTest
public with sharing class StripeCustomerGatewayMock implements StripeCustomerGateway.IStripeCustomerGateway {
    public static Set<String> failNames = new Set<String>();

    public String createCustomer(String name, String email) {
        if (failNames.contains(name)) {
            throw new AuraHandledException('Simulated Stripe failure for name: ' + name);
        }
        // Deterministic fake id
        return 'cus_' + EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(name + ':' + (email == null ? '' : email)))).substring(0, 14);
    }
}
