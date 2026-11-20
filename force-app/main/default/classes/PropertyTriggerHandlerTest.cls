@IsTest
private class PropertyTriggerHandlerTest {

    @TestSetup
    static void createTestData() {

        Sales_Region__c region = new Sales_Region__c(
            Name = 'Test Region'
        );
        insert region;

        Sales_Office__c office = new Sales_Office__c(
            Name = 'Test Sales Office',
            Sales_Region__c = region.Id
        );
        insert office;

        Contact agent = new Contact(
            LastName = 'Test Agent'
        );
        insert agent;
    }

    // Helper: retrieve the test Sales Office.
    private static Id getOfficeId() {
        return [
            SELECT Id
            FROM Sales_Office__c
            WHERE Name = 'Test Sales Office'
            LIMIT 1
        ].Id;
    }

    // Helper: create a property with a specified status.
    private static Property__c makeProperty(
        String propertyName,
        Id agentId,
        String status
    ) {
        return new Property__c(
            Name = propertyName,
            Agent__c = agentId,
            Sales_Office__c = getOfficeId(),
            Status__c = status
        );
    }

    @IsTest
    static void testFiveWorkingPropertiesAllowed() {

        Contact agent = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Test Agent'
            LIMIT 1
        ];

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            properties.add(
                makeProperty(
                    'Working Property ' + i,
                    agent.Id,
                    'Working'
                )
            );
        }

        Test.startTest();
        insert properties;
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Working'],
            'An agent should be allowed five Working properties.'
        );
    }

    @IsTest
    static void testSixthWorkingPropertyBlocked() {

        Contact agent = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Test Agent'
            LIMIT 1
        ];

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            properties.add(
                makeProperty(
                    'Existing Working Property ' + i,
                    agent.Id,
                    'Working'
                )
            );
        }

        insert properties;

        Property__c sixthProperty = makeProperty(
            'Sixth Working Property',
            agent.Id,
            'Working'
        );

        Test.startTest();

        Boolean wasBlocked = false;

        try {
            insert sixthProperty;
        } catch (DmlException e) {
            wasBlocked = true;

            System.assert(
                e.getMessage().contains(
                    'This Agent cannot have more than 5 Working properties.'
                ),
                'The expected property-limit error should be returned.'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            wasBlocked,
            'The sixth Working property should be blocked.'
        );

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Working'],
            'The agent should still have only five Working properties.'
        );
    }

    @IsTest
    static void testOpenPropertiesDoNotCount() {

        Contact agent = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Test Agent'
            LIMIT 1
        ];

        List<Property__c> openProperties = new List<Property__c>();

        for (Integer i = 1; i <= 6; i++) {
            openProperties.add(
                makeProperty(
                    'Open Property ' + i,
                    agent.Id,
                    'Open'
                )
            );
        }

        insert openProperties;

        List<Property__c> workingProperties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            workingProperties.add(
                makeProperty(
                    'Working Property ' + i,
                    agent.Id,
                    'Working'
                )
            );
        }

        Test.startTest();
        insert workingProperties;
        Test.stopTest();

        System.assertEquals(
            6,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Open'],
            'Open properties should not count toward the limit.'
        );

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Working'],
            'Five Working properties should be allowed.'
        );
    }

    @IsTest
    static void testChangingStatusFreesSlot() {

        Contact agent = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Test Agent'
            LIMIT 1
        ];

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            properties.add(
                makeProperty(
                    'Status Test Property ' + i,
                    agent.Id,
                    'Working'
                )
            );
        }

        insert properties;

        // Move one property out of Working status.
        properties[0].Status__c = 'Closed Pending Approval';

        Test.startTest();
        update properties[0];

        // A new Working property should now be allowed.
        Property__c replacement = makeProperty(
            'Replacement Working Property',
            agent.Id,
            'Working'
        );
        insert replacement;
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Working'],
            'A new Working property should be allowed after a slot is freed.'
        );
    }

    @IsTest
    static void testPropertyReassignment() {

        Contact agentA = new Contact(LastName = 'Agent A');
        Contact agentB = new Contact(LastName = 'Agent B');
        insert new List<Contact>{ agentA, agentB };

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            properties.add(
                makeProperty(
                    'Agent A Property ' + i,
                    agentA.Id,
                    'Working'
                )
            );
        }

        insert properties;

        // Reassign one Working property to Agent B.
        properties[0].Agent__c = agentB.Id;

        Test.startTest();
        update properties[0];
        Test.stopTest();

        System.assertEquals(
            4,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agentA.Id
             AND Status__c = 'Working'],
            'Agent A should have four Working properties.'
        );

        System.assertEquals(
            1,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agentB.Id
             AND Status__c = 'Working'],
            'Agent B should have one Working property.'
        );
    }

    @IsTest
    static void testBulkInsertForMultipleAgents() {

        Contact agentA = new Contact(LastName = 'Bulk Agent A');
        Contact agentB = new Contact(LastName = 'Bulk Agent B');
        insert new List<Contact>{ agentA, agentB };

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            properties.add(
                makeProperty(
                    'Bulk A Property ' + i,
                    agentA.Id,
                    'Working'
                )
            );

            properties.add(
                makeProperty(
                    'Bulk B Property ' + i,
                    agentB.Id,
                    'Working'
                )
            );
        }

        Test.startTest();
        insert properties;
        Test.stopTest();

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agentA.Id
             AND Status__c = 'Working'],
            'Agent A should have five Working properties.'
        );

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agentB.Id
             AND Status__c = 'Working'],
            'Agent B should have five Working properties.'
        );
    }

    @IsTest
    static void testBulkInsertExceedingLimit() {

        Contact agent = new Contact(
            LastName = 'Bulk Limit Agent'
        );
        insert agent;

        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 6; i++) {
            properties.add(
                makeProperty(
                    'Bulk Limit Property ' + i,
                    agent.Id,
                    'Working'
                )
            );
        }

        Test.startTest();

        // Partial-success DML: valid records may succeed while
        // records exceeding the limit are rejected.
        Database.SaveResult[] results = Database.insert(
            properties,
            false
        );

        Test.stopTest();

        Integer successCount = 0;
        Integer failureCount = 0;

        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successCount++;
            } else {
                failureCount++;
            }
        }

        System.assertEquals(
            5,
            successCount,
            'Five Working properties should be saved.'
        );

        System.assertEquals(
            1,
            failureCount,
            'Only the sixth Working property should be rejected.'
        );

        System.assertEquals(
            5,
            [SELECT COUNT()
             FROM Property__c
             WHERE Agent__c = :agent.Id
             AND Status__c = 'Working'],
            'The agent must not end up with more than five Working properties.'
        );
    }
}