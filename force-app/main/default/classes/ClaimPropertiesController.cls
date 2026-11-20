public with sharing class ClaimPropertiesController {

    public Id salesOfficeId { get; private set; }
    public String salesOfficeName { get; private set; }
    public Contact currentAgent { get; private set; }
    public List<Property__c> properties { get; private set; }

    public Map<Id, Boolean> selectedPropertyIds { get; set; }

    public Integer pageSize { get; private set; }
    public Integer pageNumber { get; private set; }
    public Integer totalProperties { get; private set; }
    public Integer totalPages { get; private set; }

    public ClaimPropertiesController() {
        pageSize = 5;
        pageNumber = 1;
        properties = new List<Property__c>();
        selectedPropertyIds = new Map<Id, Boolean>();

        loadAgent();
    }

    private void loadAgent() {
        List<Contact> agents = [
            SELECT Id, Name, Agent_User__c,
                   Sales_Office__c,
                   Default_Commission_Split__c,
                   Year_to_Date_Total_Sales__c,
                   Year_to_Date_Total_Commissions__c
            FROM Contact
            WHERE Agent_User__c = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (agents.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'No Agent Contact is linked to your Salesforce user.'
            ));
            return;
        }

        currentAgent = agents[0];
        salesOfficeId = currentAgent.Sales_Office__c;

        if (salesOfficeId == null) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Your Agent Contact has no Sales Office assigned.'
            ));
            return;
        }

        List<Sales_Office__c> offices = [
            SELECT Id, Name
            FROM Sales_Office__c
            WHERE Id = :salesOfficeId
            LIMIT 1
        ];

        if (offices.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'The assigned Sales Office could not be found.'
            ));
            return;
        }

        salesOfficeName = offices[0].Name;
        loadProperties();
    }

    public void loadProperties() {
        if (salesOfficeId == null) {
            properties = new List<Property__c>();
            totalProperties = 0;
            totalPages = 1;
            return;
        }

        totalProperties = [
            SELECT COUNT()
            FROM Property__c
            WHERE Sales_Office__c = :salesOfficeId
            AND Status__c = 'Open'
            AND Agent__c = null
        ];

        totalPages = totalProperties == 0
            ? 1
            : (Integer)Math.ceil(
                (Decimal)totalProperties / pageSize
            );

        if (pageNumber > totalPages) {
            pageNumber = totalPages;
        }

        if (pageNumber < 1) {
            pageNumber = 1;
        }

        Integer offsetRows = (pageNumber - 1) * pageSize;

        properties = [
            SELECT Id, Name, Status__c, Sales_Office__c,
                   Sales_Price__c, CreatedDate
            FROM Property__c
            WHERE Sales_Office__c = :salesOfficeId
            AND Status__c = 'Open'
            AND Agent__c = null
            ORDER BY Name
            LIMIT :pageSize
            OFFSET :offsetRows
        ];

        for (Property__c prop : properties) {
            if (!selectedPropertyIds.containsKey(prop.Id)) {
                selectedPropertyIds.put(prop.Id, false);
            }
        }
    }

    public Integer getSelectedCount() {
        Integer countSelected = 0;

        for (Id propertyId : selectedPropertyIds.keySet()) {
            if (selectedPropertyIds.get(propertyId) == true) {
                countSelected++;
            }
        }

        return countSelected;
    }

    // Claim Properties: claim and return to the Sales Office.
    public PageReference claimProperties() {
        Boolean success = performClaim();

        if (success) {
            return goToSalesOffice();
        }

        return null;
    }

    // Claim and Continue: claim and remain on this page.
    public PageReference claimAndContinue() {
        performClaim();
        return null;
    }

    // Retained for compatibility with any existing page references.
    public void claimSelected() {
        performClaim();
    }

    private Boolean performClaim() {
        Set<Id> selectedIds = new Set<Id>();

        for (Id propertyId : selectedPropertyIds.keySet()) {
            if (selectedPropertyIds.get(propertyId) == true) {
                selectedIds.add(propertyId);
            }
        }

        if (selectedIds.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Please select at least one property to claim.'
            ));
            return false;
        }

        if (currentAgent == null || salesOfficeId == null) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Your Agent Contact or Sales Office is missing.'
            ));
            return false;
        }

        // Recheck availability immediately before claiming.
        List<Property__c> availableProperties = [
            SELECT Id, Name, Status__c, Agent__c,
                   Sales_Office__c,
                   Agent_Commission_Percentage__c
            FROM Property__c
            WHERE Id IN :selectedIds
            AND Sales_Office__c = :salesOfficeId
            AND Status__c = 'Open'
            AND Agent__c = null
            FOR UPDATE
        ];

        // Do not claim anything if even one selected property
        // is no longer available.
        if (availableProperties.size() != selectedIds.size()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'One or more selected properties are no longer available. ' +
                'No properties were claimed. Refresh and try again.'
            ));
            loadProperties();
            return false;
        }

        Integer currentWorkingCount = [
            SELECT COUNT()
            FROM Property__c
            WHERE Agent__c = :currentAgent.Id
            AND Status__c = 'Working'
        ];

        if (currentWorkingCount + availableProperties.size() > 5) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'You cannot have more than 5 Working properties. ' +
                'No properties were claimed.'
            ));
            return false;
        }

        for (Property__c prop : availableProperties) {
            prop.Status__c = 'Working';
            prop.Agent__c = currentAgent.Id;
            prop.Agent_Commission_Percentage__c =
                currentAgent.Default_Commission_Split__c;
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // All-or-none update: no partial claim on failure.
            update availableProperties;

            selectedPropertyIds.clear();
            pageNumber = 1;
            loadProperties();

            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                'Selected properties were claimed successfully.'
            ));

            return true;

        } catch (Exception e) {
            Database.rollback(sp);

            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Claim failed. All changes were rolled back. Details: ' +
                e.getMessage()
            ));

            return false;
        }
    }

    // Cancel without claiming and return to the Sales Office.
    public PageReference cancelClaim() {
        selectedPropertyIds.clear();
        return goToSalesOffice();
    }

    private PageReference goToSalesOffice() {
        if (salesOfficeId == null) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Unable to return to the Sales Office because its ID is missing.'
            ));
            return null;
        }

        PageReference officePage =
            new PageReference('/' + salesOfficeId);

        officePage.setRedirect(true);
        return officePage;
    }

    public void firstPage() {
        pageNumber = 1;
        loadProperties();
    }

    public void previousPage() {
        if (pageNumber > 1) {
            pageNumber--;
        }
        loadProperties();
    }

    public void nextPage() {
        if (pageNumber < totalPages) {
            pageNumber++;
        }
        loadProperties();
    }

    public void lastPage() {
        pageNumber = totalPages;
        loadProperties();
    }

    public Boolean getHasPrevious() {
        return pageNumber > 1;
    }

    public Boolean getHasNext() {
        return pageNumber < totalPages;
    }
}