/**
 * @description Bulkified service to create Stripe Customers for Accounts using a pluggable gateway.
 * - Uses Database methods and USER_MODE for DML
 * - Return early, no SOQL/DML in loops
 * - Non-blocking failure handling (logs errors and continues)
 */
public with sharing class StripeCustomerService {
    public StripeCustomerGateway.IStripeCustomerGateway gateway { get; private set; }

    public StripeCustomerService() {
        // Default to MCP-backed gateway. For tests, inject a mock via the other constructor.
        this(new StripeCustomerGateway.McpStripeCustomerGateway());
    }
    public StripeCustomerService(StripeCustomerGateway.IStripeCustomerGateway gateway) {
        this.gateway = gateway;
    }

    /**
     * @param accts List of Accounts (inserted) to process
     * @description For each account missing Stripe_Customer_Id__c, call gateway and update the field.
     * Email mapping: use PersonEmail when available; otherwise omit.
     */
    public void createStripeCustomersForAccounts(List<Account> accts) {
        if (accts == null || accts.isEmpty()) {
            return; // Return early
        }

        // Filter candidates: no existing Stripe id
        List<Account> candidates = new List<Account>();
        for (Account a : accts) {
            if (a == null) continue;
            // Dynamic check for field existence
            try {
                Object val = a.get('Stripe_Customer_Id__c');
                if (val == null || String.isBlank(String.valueOf(val))) {
                    candidates.add(a);
                }
            } catch (Exception e) {
                // Field not present, treat as if no value
                candidates.add(a);
            }
        }
        if (candidates.isEmpty()) {
            return;
        }

        // Collect updates
        List<Account> toUpdate = new List<Account>();
        // Non-blocking: gather failures into debug logs (in real orgs, prefer a logging object / PE)
        for (Account a : candidates) {
            try {
                String name = a.Name;
                String email = null;
                // Safely try to read PersonEmail if present (works whether or not Person Accounts are enabled)
                try {
                    Object val = a.get('PersonEmail');
                    if (val != null) {
                        email = String.valueOf(val);
                    }
                } catch (Exception ignoreField) {
                    // Field not available in this org; omit email
                }

                // Call gateway
                String stripeId = gateway.createCustomer(name, email);
                if (!String.isBlank(stripeId)) {
                    Account upd = new Account(Id = a.Id);
                    try {
                        // Use dynamic put to avoid compile-time dependency during initial deployments
                        upd.put('Stripe_Customer_Id__c', stripeId);
                    } catch (Exception e2) {
                        System.debug(LoggingLevel.ERROR, 'Could not set Stripe_Customer_Id__c for Account Id=' + a.Id + ' error=' + e2.getMessage());
                    }
                    toUpdate.add(upd);
                }
            } catch (Exception e) {
                // Non-blocking error handling per user choice
                System.debug(LoggingLevel.ERROR, 'Stripe customer creation failed for Account Id=' + a.Id + ' error=' + e.getMessage());
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.DMLOptions dmlOpts = new Database.DMLOptions();
            // USER_MODE DML per rules
            Database.SaveResult[] results = Database.update(toUpdate, /*allOrNone*/ false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Failed to update Stripe_Customer_Id__c for Account Id=' + toUpdate[i].Id + ' error=' + err.getMessage());
                    }
                }
            }
        }
    }
}
