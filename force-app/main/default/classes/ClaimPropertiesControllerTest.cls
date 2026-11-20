@IsTest
private class ClaimPropertiesControllerTest {

    @TestSetup
    static void setupData() {

        Sales_Region__c region = new Sales_Region__c(
            Name = 'Test Region',
            Regional_Manager__c = UserInfo.getUserId()
        );
        insert region;

        Sales_Office__c office = new Sales_Office__c(
            Name = 'Test Chennai Office',
            Sales_Region__c = region.Id
        );
        insert office;

        Contact agent = new Contact(
            LastName = 'Test Agent',
            Agent_User__c = UserInfo.getUserId(),
            Sales_Office__c = office.Id,
            Default_Commission_Split__c = 40
        );
        insert agent;
    }

    private static Contact getAgent() {
        return [
            SELECT Id, Agent_User__c, Sales_Office__c,
                   Default_Commission_Split__c
            FROM Contact
            WHERE Agent_User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
    }

    private static Sales_Office__c getOffice() {
        return [
            SELECT Id, Name
            FROM Sales_Office__c
            LIMIT 1
        ];
    }

    private static Property__c makeProperty(
        String propertyName,
        Id officeId,
        Id agentId,
        String status
    ) {
        return new Property__c(
            Name = propertyName,
            Sales_Office__c = officeId,
            Agent__c = agentId,
            Status__c = status,
            Sales_Price__c = 2000000,
            Sale_Date__c = Date.today(),
            Agent_Commission_Percentage__c = 40
        );
    }

    @IsTest
    static void testConstructorAndLoadProperties() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        insert new List<Property__c>{
            makeProperty('Open 01', office.Id, null, 'Open'),
            makeProperty('Open 02', office.Id, null, 'Open'),
            makeProperty('Open 03', office.Id, null, 'Open')
        };

        Test.startTest();
        ClaimPropertiesController controller =
            new ClaimPropertiesController();
        Test.stopTest();

        System.assertEquals(agent.Id, controller.currentAgent.Id);
        System.assertEquals(office.Id, controller.salesOfficeId);
        System.assertEquals(office.Name, controller.salesOfficeName);
        System.assertEquals(5, controller.pageSize);
        System.assertEquals(1, controller.pageNumber);
        System.assertEquals(3, controller.totalProperties);
        System.assertEquals(1, controller.totalPages);
        System.assertEquals(3, controller.properties.size());
    }

    @IsTest
    static void testPaginationAndSelectionRetention() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        List<Property__c> records = new List<Property__c>();

        for (Integer i = 1; i <= 7; i++) {
            records.add(
                makeProperty(
                    'Open Property ' + i,
                    office.Id,
                    null,
                    'Open'
                )
            );
        }
        insert records;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        System.assertEquals(5, controller.properties.size());
        System.assertEquals(2, controller.totalPages);
        System.assertEquals(false, controller.getHasPrevious());
        System.assertEquals(true, controller.getHasNext());

        Id firstPropertyId = controller.properties[0].Id;
        controller.selectedPropertyIds.put(firstPropertyId, true);

        controller.nextPage();

        System.assertEquals(2, controller.properties.size());
        System.assertEquals(2, controller.pageNumber);
        System.assertEquals(true, controller.getHasPrevious());
        System.assertEquals(false, controller.getHasNext());
        System.assertEquals(1, controller.getSelectedCount());

        controller.previousPage();
        System.assertEquals(1, controller.pageNumber);

        controller.lastPage();
        System.assertEquals(2, controller.pageNumber);

        controller.firstPage();
        System.assertEquals(1, controller.pageNumber);

        controller.nextPage();
        controller.nextPage();
        System.assertEquals(2, controller.pageNumber);

        controller.firstPage();
        System.assertEquals(1, controller.pageNumber);
    }

    @IsTest
    static void testNoAgentContact() {

        Contact agent = getAgent();
        agent.Agent_User__c = null;
        update agent;

        Test.startTest();
        ClaimPropertiesController controller =
            new ClaimPropertiesController();
        Test.stopTest();

        System.assertEquals(null, controller.currentAgent);
        System.assertEquals(null, controller.salesOfficeId);
        System.assertEquals(0, controller.properties.size());
        System.assert(!ApexPages.getMessages().isEmpty());
    }

    @IsTest
    static void testAgentWithoutSalesOffice() {

        Contact agent = getAgent();
        agent.Sales_Office__c = null;
        update agent;

        Test.startTest();
        ClaimPropertiesController controller =
            new ClaimPropertiesController();
        Test.stopTest();

        System.assertNotEquals(null, controller.currentAgent);
        System.assertEquals(null, controller.salesOfficeId);
        System.assert(!ApexPages.getMessages().isEmpty());
    }

    @IsTest
    static void testNoPropertySelected() {

        Sales_Office__c office = getOffice();

        insert makeProperty(
            'Open No Selection',
            office.Id,
            null,
            'Open'
        );

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        Test.startTest();
        PageReference result = controller.claimAndContinue();
        Test.stopTest();

        System.assertEquals(null, result);

        Property__c prop = [
            SELECT Status__c, Agent__c
            FROM Property__c
            WHERE Name = 'Open No Selection'
            LIMIT 1
        ];

        System.assertEquals('Open', prop.Status__c);
        System.assertEquals(null, prop.Agent__c);
        System.assert(!ApexPages.getMessages().isEmpty());
    }

    @IsTest
    static void testSuccessfulClaimAndContinue() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        Property__c prop = makeProperty(
            'Claim Continue Property',
            office.Id,
            null,
            'Open'
        );
        insert prop;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(prop.Id, true);

        Test.startTest();
        PageReference result = controller.claimAndContinue();
        Test.stopTest();

        System.assertEquals(null, result);

        Property__c claimed = [
            SELECT Status__c, Agent__c,
                   Agent_Commission_Percentage__c
            FROM Property__c
            WHERE Id = :prop.Id
        ];

        System.assertEquals('Working', claimed.Status__c);
        System.assertEquals(agent.Id, claimed.Agent__c);
        System.assertEquals(
            40,
            claimed.Agent_Commission_Percentage__c
        );
        System.assertEquals(0, controller.getSelectedCount());
    }

    @IsTest
    static void testSuccessfulClaimPropertiesNavigation() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        Property__c prop = makeProperty(
            'Claim Return Property',
            office.Id,
            null,
            'Open'
        );
        insert prop;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(prop.Id, true);

        Test.startTest();
        PageReference result = controller.claimProperties();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('/' + office.Id, result.getUrl());
        System.assertEquals(true, result.getRedirect());

        Property__c claimed = [
            SELECT Status__c, Agent__c
            FROM Property__c
            WHERE Id = :prop.Id
        ];

        System.assertEquals('Working', claimed.Status__c);
        System.assertEquals(agent.Id, claimed.Agent__c);
    }

    @IsTest
    static void testFiveWorkingPropertyLimit() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        List<Property__c> records = new List<Property__c>();

        for (Integer i = 1; i <= 5; i++) {
            records.add(
                makeProperty(
                    'Working Property ' + i,
                    office.Id,
                    agent.Id,
                    'Working'
                )
            );
        }

        records.add(
            makeProperty(
                'Sixth Open Property',
                office.Id,
                null,
                'Open'
            )
        );

        insert records;

        Property__c openProperty = [
            SELECT Id
            FROM Property__c
            WHERE Name = 'Sixth Open Property'
            LIMIT 1
        ];

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(openProperty.Id, true);

        Test.startTest();
        controller.claimAndContinue();
        Test.stopTest();

        Property__c unchanged = [
            SELECT Status__c, Agent__c
            FROM Property__c
            WHERE Id = :openProperty.Id
        ];

        System.assertEquals('Open', unchanged.Status__c);
        System.assertEquals(null, unchanged.Agent__c);
        System.assert(!ApexPages.getMessages().isEmpty());
    }

    @IsTest
    static void testPropertyNoLongerAvailable() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        Property__c prop = makeProperty(
            'Unavailable Property',
            office.Id,
            null,
            'Open'
        );
        insert prop;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(prop.Id, true);

        // Simulate another user claiming the property first.
        prop.Status__c = 'Working';
        prop.Agent__c = agent.Id;
        update prop;

        Test.startTest();
        controller.claimAndContinue();
        Test.stopTest();

        Property__c current = [
            SELECT Status__c, Agent__c
            FROM Property__c
            WHERE Id = :prop.Id
        ];

        System.assertEquals('Working', current.Status__c);
        System.assertEquals(agent.Id, current.Agent__c);
        System.assert(!ApexPages.getMessages().isEmpty());
    }

    @IsTest
    static void testClaimSelectedCompatibility() {

        Contact agent = getAgent();
        Sales_Office__c office = getOffice();

        Property__c prop = makeProperty(
            'Compatibility Claim',
            office.Id,
            null,
            'Open'
        );
        insert prop;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(prop.Id, true);

        Test.startTest();
        controller.claimSelected();
        Test.stopTest();

        Property__c claimed = [
            SELECT Status__c, Agent__c
            FROM Property__c
            WHERE Id = :prop.Id
        ];

        System.assertEquals('Working', claimed.Status__c);
        System.assertEquals(agent.Id, claimed.Agent__c);
    }

    @IsTest
    static void testCancelAndPageNavigation() {

        Sales_Office__c office = getOffice();

        List<Property__c> records = new List<Property__c>();

        for (Integer i = 1; i <= 7; i++) {
            records.add(
                makeProperty(
                    'Cancel Property ' + i,
                    office.Id,
                    null,
                    'Open'
                )
            );
        }
        insert records;

        ClaimPropertiesController controller =
            new ClaimPropertiesController();

        controller.selectedPropertyIds.put(
            controller.properties[0].Id,
            true
        );

        Test.startTest();
        PageReference result = controller.cancelClaim();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('/' + office.Id, result.getUrl());
        System.assertEquals(true, result.getRedirect());
        System.assertEquals(0, controller.getSelectedCount());
    }
}