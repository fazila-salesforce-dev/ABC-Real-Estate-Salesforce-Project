@IsTest
private class ApproveCommissionsControllerTest {

    private static final Decimal SALES_PRICE = 2000000;
    private static final Decimal COMMISSION_SPLIT = 40;

    @TestSetup
    static void createTestData() {

        // 1. Create Sales Region
        Sales_Region__c region = new Sales_Region__c(
            Name = 'Test Region',
            Regional_Manager__c = UserInfo.getUserId()
        );
        insert region;

        // 2. Create Sales Office
        Sales_Office__c office = new Sales_Office__c(
            Name = 'Test Office',
            Sales_Region__c = region.Id
        );
        insert office;

        // 3. Create Agent
        Contact agent = new Contact(
            LastName = 'Test Agent',
            Default_Commission_Split__c = COMMISSION_SPLIT
        );
        insert agent;

        // 4. Create seven properties for pagination and approval tests
        List<Property__c> properties = new List<Property__c>();

        for (Integer i = 1; i <= 7; i++) {
            properties.add(new Property__c(
                Name = 'Test Property ' + i,
                Sales_Office__c = office.Id,
                Agent__c = agent.Id,
                Sales_Price__c = SALES_PRICE,
                Sale_Date__c = Date.today(),
                Status__c = 'Closed Pending Approval',
                Agent_Commission_Percentage__c = COMMISSION_SPLIT
            ));
        }

        insert properties;
    }

    // Get the region assigned to the current test user.
    private static Sales_Region__c getTestRegion() {
        return [
            SELECT Id, Name, Regional_Manager__c
            FROM Sales_Region__c
            WHERE Name = 'Test Region'
            LIMIT 1
        ];
    }

    // Get a property that is still awaiting approval.
    private static Property__c getPendingProperty() {
        return [
            SELECT Id, Name, Status__c, Sales_Price__c,
                   Sale_Date__c, Agent__c,
                   Agent_Commission_Percentage__c,
                   Agent_Commission_Amount__c
            FROM Property__c
            WHERE Status__c = 'Closed Pending Approval'
            ORDER BY Name
            LIMIT 1
        ];
    }

    // Create the controller for the test region.
    private static ApproveCommissionsController createController(
        Id regionId
    ) {
        Test.setCurrentPage(Page.ApproveCommissions);

        ApexPages.currentPage().getParameters().put(
            'id',
            String.valueOf(regionId)
        );

        return new ApproveCommissionsController();
    }

    // Select a property on the displayed page.
    private static void selectProperty(
        ApproveCommissionsController controller,
        Id propertyId,
        Decimal commissionSplit
    ) {
        Boolean found = false;

        for (ApproveCommissionsController.PropertyRow row :
             controller.pageRows) {

            if (row.propertyRecord.Id == propertyId) {
                row.selected = true;

                row.propertyRecord.Agent_Commission_Percentage__c =
                    commissionSplit;

                controller.percentageByPropertyId.put(
                    propertyId,
                    commissionSplit
                );

                found = true;
                break;
            }
        }

        System.assert(
            found,
            'Property ' + propertyId +
            ' was not found on the current page.'
        );
    }

    // Collect messages to make approval failures easier to diagnose.
    private static String getApprovalMessages() {
        String details = '';

        for (ApexPages.Message msg : ApexPages.getMessages()) {
            details +=
                String.valueOf(msg.getSeverity()) + ': ' +
                msg.getSummary() + ' | ';
        }

        return details;
    }

    // Test initial loading and record counts.
    @IsTest
    static void testControllerLoadsProperties() {

        Sales_Region__c region = getTestRegion();

        ApproveCommissionsController controller =
            createController(region.Id);

        System.assertEquals(region.Id, controller.regionId);
        System.assertEquals('Test Region', controller.regionName);
        System.assertEquals(5, controller.pageRows.size());
        System.assertEquals(7, controller.getTotalRecords());
        System.assertEquals(2, controller.getTotalPages());
    }

    // Test first, next, previous, and last page navigation.
    @IsTest
    static void testPagination() {

        Sales_Region__c region = getTestRegion();

        ApproveCommissionsController controller =
            createController(region.Id);

        System.assertEquals(1, controller.pageNumber);
        System.assertEquals(true, controller.getHasNext());
        System.assertEquals(false, controller.getHasPrevious());

        controller.nextPage();

        System.assertEquals(2, controller.pageNumber);
        System.assertEquals(2, controller.pageRows.size());
        System.assertEquals(false, controller.getHasNext());
        System.assertEquals(true, controller.getHasPrevious());

        controller.previousPage();

        System.assertEquals(1, controller.pageNumber);
        System.assertEquals(5, controller.pageRows.size());

        controller.lastPage();
        System.assertEquals(2, controller.pageNumber);

        controller.firstPage();
        System.assertEquals(1, controller.pageNumber);
    }

    // Test that a user who is not the assigned manager is denied access.
    @IsTest
    static void testUnauthorizedUserCannotLoadRegion() {

        Sales_Region__c region = getTestRegion();

        User otherUser = new User(
            Alias = 'otherusr',
            Email = 'otheruser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Other User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            ProfileId = UserInfo.getProfileId(),
            Username = 'otheruser.' +
                System.currentTimeMillis() + '@example.com'
        );
        insert otherUser;

        Test.setCurrentPage(Page.ApproveCommissions);

        ApexPages.currentPage().getParameters().put(
            'id',
            String.valueOf(region.Id)
        );

        Test.startTest();

        System.runAs(otherUser) {
            ApproveCommissionsController controller =
                new ApproveCommissionsController();

            System.assertEquals(null, controller.regionId);
            System.assertNotEquals(null, controller.message);
        }

        Test.stopTest();
    }

    // Test successful approval and redirection to the region.
    @IsTest
    static void testSuccessfulApproval() {

        Sales_Region__c region = getTestRegion();
        Property__c propertyRecord = getPendingProperty();

        ApproveCommissionsController controller =
            createController(region.Id);

        selectProperty(controller, propertyRecord.Id, 40);

        Test.startTest();
        PageReference result = controller.approveSelected();
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Approval failed. Controller messages: ' +
            getApprovalMessages()
        );

        Property__c updatedProperty = [
            SELECT Status__c,
                   Sale_Date__c,
                   Agent_Commission_Percentage__c,
                   Agent_Commission_Amount__c
            FROM Property__c
            WHERE Id = :propertyRecord.Id
        ];

        System.assertEquals(
            'Closed Approved',
            updatedProperty.Status__c,
            'Approval messages: ' + getApprovalMessages()
        );

        System.assertEquals(
            40,
            updatedProperty.Agent_Commission_Percentage__c
        );

        System.assertEquals(
            24000,
            updatedProperty.Agent_Commission_Amount__c
        );
    }

    // Test approval while remaining on the current screen.
    @IsTest
    static void testApproveAndContinue() {

        Sales_Region__c region = getTestRegion();
        Property__c propertyRecord = getPendingProperty();

        ApproveCommissionsController controller =
            createController(region.Id);

        selectProperty(controller, propertyRecord.Id, 40);

        Test.startTest();
        PageReference result = controller.approveAndContinue();
        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'approveAndContinue should remain on the current page.'
        );

        Property__c updatedProperty = [
            SELECT Status__c, Agent_Commission_Amount__c
            FROM Property__c
            WHERE Id = :propertyRecord.Id
        ];

        System.assertEquals(
            'Closed Approved',
            updatedProperty.Status__c,
            'Approval messages: ' + getApprovalMessages()
        );

        System.assertEquals(
            24000,
            updatedProperty.Agent_Commission_Amount__c,
            'Approval messages: ' + getApprovalMessages()
        );
    }

    // Test that approval is rejected if no property is selected.
    @IsTest
    static void testApprovalRequiresSelection() {

        Sales_Region__c region = getTestRegion();

        ApproveCommissionsController controller =
            createController(region.Id);

        Test.startTest();
        PageReference result = controller.approveSelected();
        Test.stopTest();

        System.assertEquals(null, result);
        System.assertEquals(0, controller.selectedIds.size());

        System.assert(
            ApexPages.getMessages().size() > 0,
            'An error message should appear when nothing is selected.'
        );

        System.assertEquals(
            'Please select at least one property.',
            ApexPages.getMessages()[0].getSummary()
        );
    }

    // Test overriding the agent commission split to 50%.
    @IsTest
    static void testCommissionPercentageOverride() {

        Sales_Region__c region = getTestRegion();
        Property__c propertyRecord = getPendingProperty();

        ApproveCommissionsController controller =
            createController(region.Id);

        selectProperty(controller, propertyRecord.Id, 50);

        Test.startTest();
        controller.approveAndContinue();
        Test.stopTest();

        Property__c updatedProperty = [
            SELECT Status__c,
                   Agent_Commission_Percentage__c,
                   Agent_Commission_Amount__c
            FROM Property__c
            WHERE Id = :propertyRecord.Id
        ];

        System.assertEquals(
            'Closed Approved',
            updatedProperty.Status__c,
            'Approval messages: ' + getApprovalMessages()
        );

        System.assertEquals(
            50,
            updatedProperty.Agent_Commission_Percentage__c,
            'Approval messages: ' + getApprovalMessages()
        );

        System.assertEquals(
            30000,
            updatedProperty.Agent_Commission_Amount__c,
            'Approval messages: ' + getApprovalMessages()
        );
    }

    // Test cancellation returns to the Sales Region record.
    @IsTest
    static void testCancelReturnsToRegion() {

        Sales_Region__c region = getTestRegion();

        ApproveCommissionsController controller =
            createController(region.Id);

        PageReference result = controller.cancel();

        System.assertNotEquals(null, result);

        System.assertEquals(
            '/' + region.Id,
            result.getUrl()
        );
    }

    // Test that selections are transferred from rows to selectedIds.
    @IsTest
    static void testSelectionIsSavedFromPageRows() {

        Sales_Region__c region = getTestRegion();
        Property__c propertyRecord = getPendingProperty();

        ApproveCommissionsController controller =
            createController(region.Id);

        selectProperty(controller, propertyRecord.Id, 40);
        controller.savePageState();

        System.assert(
            controller.selectedIds.contains(propertyRecord.Id),
            'The selected row ID should be saved in selectedIds.'
        );

        System.assertEquals(1, controller.getSelectedCount());
    }
}