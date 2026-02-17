/**
 * @description Trigger handler for Account to create Stripe Customers on after insert.
 * - One trigger per object pattern
 * - Bulkified, calls service layer
 * - Non-blocking failures per user preference
 */
public with sharing class AccountTriggerHandler {
    public static void afterInsert(List<Account> newList) {
        if (newList == null || newList.isEmpty()) return;
        // Service handles filtering Accounts that already have Stripe Id
        StripeCustomerService svc = new StripeCustomerService();
        svc.createStripeCustomersForAccounts(newList);
    }
}
