trigger PropertyTrigger on Property__c (
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    // Preserve the existing five-Working-property validation
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            PropertyTriggerHandler.validatePropertyLimit(
                Trigger.new,
                null
            );
        }

        if (Trigger.isUpdate) {
            PropertyTriggerHandler.validatePropertyLimit(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }

    // Recalculate YTD totals after property changes
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PropertyTriggerHandler.updateYtdTotals(
                Trigger.new,
                null,
                null
            );
        }

        if (Trigger.isUpdate) {
            PropertyTriggerHandler.updateYtdTotals(
                Trigger.new,
                Trigger.oldMap,
                null
            );
        }

        if (Trigger.isDelete) {
            PropertyTriggerHandler.updateYtdTotals(
                null,
                null,
                Trigger.old
            );
        }

        if (Trigger.isUndelete) {
            PropertyTriggerHandler.updateYtdTotals(
                Trigger.new,
                null,
                null
            );
        }
    }
}