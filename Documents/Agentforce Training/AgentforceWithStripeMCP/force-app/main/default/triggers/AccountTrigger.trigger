/**
 * @description One trigger per object for Account.
 * After insert: create Stripe Customers via handler.
 */
trigger AccountTrigger on Account (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        AccountTriggerHandler.afterInsert(Trigger.new);
    }
}
