public class PropertyTriggerHandler {

    // Enforce a maximum of five Working properties per Agent.
    public static void validatePropertyLimit(
        List<Property__c> newProperties,
        Map<Id, Property__c> oldMap
    ) {
        Set<Id> agentIds = new Set<Id>();
        Set<Id> excludedPropertyIds = new Set<Id>();

        // Collect affected Agents and exclude records being updated.
        for (Property__c prop : newProperties) {
            if (prop.Agent__c != null) {
                agentIds.add(prop.Agent__c);
            }

            if (oldMap != null && prop.Id != null) {
                excludedPropertyIds.add(prop.Id);

                Property__c oldProp = oldMap.get(prop.Id);

                if (oldProp != null && oldProp.Agent__c != null) {
                    agentIds.add(oldProp.Agent__c);
                }
            }
        }

        if (agentIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> workingCounts = new Map<Id, Integer>();

        // Count existing Working properties for each Agent.
        for (AggregateResult ar : [
            SELECT Agent__c agentId, COUNT(Id) total
            FROM Property__c
            WHERE Agent__c IN :agentIds
            AND Status__c = 'Working'
            AND Id NOT IN :excludedPropertyIds
            GROUP BY Agent__c
        ]) {
            workingCounts.put(
                (Id) ar.get('agentId'),
                (Integer) ar.get('total')
            );
        }

        // Count incoming Working properties, including bulk inserts.
        for (Property__c prop : newProperties) {
            if (
                prop.Agent__c == null ||
                prop.Status__c != 'Working'
            ) {
                continue;
            }

            Integer countForAgent =
                workingCounts.containsKey(prop.Agent__c)
                    ? workingCounts.get(prop.Agent__c)
                    : 0;

            if (countForAgent >= 5) {
                prop.addError(
                    'This Agent cannot have more than 5 Working properties.'
                );
            } else {
                workingCounts.put(
                    prop.Agent__c,
                    countForAgent + 1
                );
            }
        }
    }

    // Recalculate YTD totals for affected Contacts and Sales Offices.
    public static void updateYtdTotals(
        List<Property__c> newProperties,
        Map<Id, Property__c> oldMap,
        List<Property__c> deletedProperties
    ) {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> officeIds = new Set<Id>();

        if (newProperties != null) {
            for (Property__c prop : newProperties) {
                if (prop.Agent__c != null) {
                    contactIds.add(prop.Agent__c);
                }

                if (prop.Sales_Office__c != null) {
                    officeIds.add(prop.Sales_Office__c);
                }
            }
        }

        if (oldMap != null) {
            for (Property__c prop : oldMap.values()) {
                if (prop.Agent__c != null) {
                    contactIds.add(prop.Agent__c);
                }

                if (prop.Sales_Office__c != null) {
                    officeIds.add(prop.Sales_Office__c);
                }
            }
        }

        if (deletedProperties != null) {
            for (Property__c prop : deletedProperties) {
                if (prop.Agent__c != null) {
                    contactIds.add(prop.Agent__c);
                }

                if (prop.Sales_Office__c != null) {
                    officeIds.add(prop.Sales_Office__c);
                }
            }
        }

        if (contactIds.isEmpty() && officeIds.isEmpty()) {
            return;
        }

        Date yearStart = Date.newInstance(
            Date.today().year(), 1, 1
        );

        Date nextYearStart = Date.newInstance(
            Date.today().year() + 1, 1, 1
        );

        Map<Id, Decimal> contactSales = new Map<Id, Decimal>();
        Map<Id, Decimal> contactCommissions = new Map<Id, Decimal>();
        Map<Id, Decimal> officeSales = new Map<Id, Decimal>();

        for (Id contactId : contactIds) {
            contactSales.put(contactId, 0);
            contactCommissions.put(contactId, 0);
        }

        for (Id officeId : officeIds) {
            officeSales.put(officeId, 0);
        }

        // Contact YTD sales: pending approval and approved sales.
        if (!contactIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Agent__c agentId,
                       SUM(Sales_Price__c) totalSales
                FROM Property__c
                WHERE Agent__c IN :contactIds
                AND Status__c IN (
                    'Closed Pending Approval',
                    'Closed Approved'
                )
                AND Sale_Date__c >= :yearStart
                AND Sale_Date__c < :nextYearStart
                GROUP BY Agent__c
            ]) {
                contactSales.put(
                    (Id) ar.get('agentId'),
                    (Decimal) ar.get('totalSales')
                );
            }

            // Contact YTD commissions: approved sales only.
            for (AggregateResult ar : [
                SELECT Agent__c agentId,
                       SUM(Agent_Commission_Amount__c) totalCommission
                FROM Property__c
                WHERE Agent__c IN :contactIds
                AND Status__c = 'Closed Approved'
                AND Sale_Date__c >= :yearStart
                AND Sale_Date__c < :nextYearStart
                GROUP BY Agent__c
            ]) {
                contactCommissions.put(
                    (Id) ar.get('agentId'),
                    (Decimal) ar.get('totalCommission')
                );
            }
        }

        // Sales Office YTD sales: pending approval and approved sales.
        if (!officeIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Sales_Office__c officeId,
                       SUM(Sales_Price__c) totalSales
                FROM Property__c
                WHERE Sales_Office__c IN :officeIds
                AND Status__c IN (
                    'Closed Pending Approval',
                    'Closed Approved'
                )
                AND Sale_Date__c >= :yearStart
                AND Sale_Date__c < :nextYearStart
                GROUP BY Sales_Office__c
            ]) {
                officeSales.put(
                    (Id) ar.get('officeId'),
                    (Decimal) ar.get('totalSales')
                );
            }
        }

        // Update Contact totals only when values have changed.
        List<Contact> contactsToUpdate = new List<Contact>();

        if (!contactIds.isEmpty()) {
            for (Contact con : [
                SELECT Id,
                       Year_to_Date_Total_Sales__c,
                       Year_to_Date_Total_Commissions__c
                FROM Contact
                WHERE Id IN :contactIds
            ]) {
                Decimal calculatedSales = contactSales.get(con.Id);
                Decimal calculatedCommissions =
                    contactCommissions.get(con.Id);

                if (calculatedSales == null) {
                    calculatedSales = 0;
                }

                if (calculatedCommissions == null) {
                    calculatedCommissions = 0;
                }

                Decimal existingSales =
                    con.Year_to_Date_Total_Sales__c;

                Decimal existingCommissions =
                    con.Year_to_Date_Total_Commissions__c;

                if (existingSales == null) {
                    existingSales = 0;
                }

                if (existingCommissions == null) {
                    existingCommissions = 0;
                }

                if (
                    existingSales != calculatedSales ||
                    existingCommissions != calculatedCommissions
                ) {
                    con.Year_to_Date_Total_Sales__c =
                        calculatedSales;

                    con.Year_to_Date_Total_Commissions__c =
                        calculatedCommissions;

                    contactsToUpdate.add(con);
                }
            }
        }

        // Update Sales Offices only when YTD sales has changed.
        List<Sales_Office__c> officesToUpdate =
            new List<Sales_Office__c>();

        if (!officeIds.isEmpty()) {
            for (Sales_Office__c office : [
                SELECT Id, Year_to_Date_Sales__c
                FROM Sales_Office__c
                WHERE Id IN :officeIds
            ]) {
                Decimal calculatedSales = officeSales.get(office.Id);

                if (calculatedSales == null) {
                    calculatedSales = 0;
                }

                Decimal existingSales = office.Year_to_Date_Sales__c;

                if (existingSales == null) {
                    existingSales = 0;
                }

                if (existingSales != calculatedSales) {
                    office.Year_to_Date_Sales__c = calculatedSales;
                    officesToUpdate.add(office);
                }
            }
        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }

        if (!officesToUpdate.isEmpty()) {
            update officesToUpdate;
        }
    }
}