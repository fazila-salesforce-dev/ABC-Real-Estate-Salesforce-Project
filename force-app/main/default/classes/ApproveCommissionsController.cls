public class ApproveCommissionsController {

    public Id regionId { get; set; }
    public String regionName { get; set; }
    public String message { get; set; }

    public Integer pageNumber { get; set; }
    public Integer pageSize { get; set; }

    public List<PropertyRow> pageRows { get; set; }
    public Set<Id> selectedIds { get; set; }
    public Map<Id, Decimal> percentageByPropertyId { get; set; }

    public Boolean selectCurrentPage { get; set; }

    public ApproveCommissionsController() {
        pageNumber = 1;
        pageSize = 5;

        pageRows = new List<PropertyRow>();
        selectedIds = new Set<Id>();
        percentageByPropertyId = new Map<Id, Decimal>();

        selectCurrentPage = false;

        String suppliedId = ApexPages.currentPage()
            .getParameters().get('id');

        if (String.isBlank(suppliedId)) {
            suppliedId = ApexPages.currentPage()
                .getParameters().get('regionId');
        }

        if (String.isBlank(suppliedId)) {
            message = 'Sales Region ID is missing.';
            return;
        }

        try {
            regionId = (Id) suppliedId;

            List<Sales_Region__c> regions = [
                SELECT Id, Name
                FROM Sales_Region__c
                WHERE Id = :regionId
                AND Regional_Manager__c = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (regions.isEmpty()) {
                regionId = null;
                message =
                    'You are not authorized to approve commissions for this region.';
                return;
            }

            regionName = regions[0].Name;
            loadProperties();

        } catch (Exception e) {
            regionId = null;
            message = 'Unable to load the Sales Region: ' +
                e.getMessage();
        }
    }

    public Integer getTotalRecords() {
        if (regionId == null) {
            return 0;
        }

        return [
            SELECT COUNT()
            FROM Property__c
            WHERE Status__c = 'Closed Pending Approval'
            AND Sales_Office__r.Sales_Region__c = :regionId
        ];
    }

    public Integer getTotalPages() {
        Integer total = getTotalRecords();

        if (total == 0) {
            return 1;
        }

        return (Integer) Math.ceil(
            (Decimal) total / pageSize
        );
    }

    public Integer getSelectedCount() {
        return selectedIds.size();
    }

    public Boolean getHasPrevious() {
        return pageNumber > 1;
    }

    public Boolean getHasNext() {
        return pageNumber < getTotalPages();
    }

    private void loadProperties() {
        pageRows = new List<PropertyRow>();

        if (regionId == null) {
            return;
        }

        Integer pages = getTotalPages();

        if (pageNumber < 1) {
            pageNumber = 1;
        }

        if (pageNumber > pages) {
            pageNumber = pages;
        }

        Integer rowOffset = (pageNumber - 1) * pageSize;

        List<Property__c> records = [
            SELECT Id, Name, Status__c, Sales_Price__c,
                   Sale_Date__c, Agent__c, Agent__r.Name,
                   Agent_Commission_Percentage__c,
                   Agent_Commission_Amount__c,
                   Sales_Office__c, Sales_Office__r.Name,
                   Sales_Office__r.Year_to_Date_Sales__c,
                   Sales_Office__r.Sales_Region__c
            FROM Property__c
            WHERE Status__c = 'Closed Pending Approval'
            AND Sales_Office__r.Sales_Region__c = :regionId
            ORDER BY Sales_Office__r.Name, Agent__r.Name, Name
            LIMIT :pageSize
            OFFSET :rowOffset
        ];

        for (Property__c p : records) {
            PropertyRow row = new PropertyRow();

            row.propertyRecord = p;
            row.selected = selectedIds.contains(p.Id);

            if (percentageByPropertyId.containsKey(p.Id)) {
                p.Agent_Commission_Percentage__c =
                    percentageByPropertyId.get(p.Id);
            } else {
                percentageByPropertyId.put(
                    p.Id,
                    p.Agent_Commission_Percentage__c
                );
            }

            pageRows.add(row);
        }

        selectCurrentPage = !pageRows.isEmpty();

        for (PropertyRow row : pageRows) {
            if (!row.selected) {
                selectCurrentPage = false;
                break;
            }
        }
    }

    public void savePageState() {
        for (PropertyRow row : pageRows) {
            Id propertyId = row.propertyRecord.Id;

            if (row.selected) {
                selectedIds.add(propertyId);

                percentageByPropertyId.put(
                    propertyId,
                    row.propertyRecord.Agent_Commission_Percentage__c
                );
            } else {
                selectedIds.remove(propertyId);
            }
        }
    }

    public void updateSelectedCount() {
        savePageState();
    }

    public void toggleCurrentPage() {
        savePageState();

        for (PropertyRow row : pageRows) {
            row.selected = selectCurrentPage;

            if (selectCurrentPage) {
                selectedIds.add(row.propertyRecord.Id);
            } else {
                selectedIds.remove(row.propertyRecord.Id);
            }
        }
    }

    public void firstPage() {
        savePageState();
        pageNumber = 1;
        loadProperties();
    }

    public void previousPage() {
        savePageState();

        if (pageNumber > 1) {
            pageNumber--;
        }

        loadProperties();
    }

    public void nextPage() {
        savePageState();

        if (pageNumber < getTotalPages()) {
            pageNumber++;
        }

        loadProperties();
    }

    public void lastPage() {
        savePageState();
        pageNumber = getTotalPages();
        loadProperties();
    }

    public PageReference approveSelected() {
        Boolean success = performApproval();

        if (success && regionId != null) {
            PageReference regionPage =
                new PageReference('/' + regionId);

            regionPage.setRedirect(true);
            return regionPage;
        }

        return null;
    }

    public PageReference approveAndContinue() {
        performApproval();
        return null;
    }

    private Boolean performApproval() {

        if (regionId == null) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'You are not authorized to approve commissions for this region.'
            ));
            return false;
        }

        List<Sales_Region__c> authorizedRegions = [
            SELECT Id
            FROM Sales_Region__c
            WHERE Id = :regionId
            AND Regional_Manager__c = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (authorizedRegions.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Only the assigned Regional Manager can approve commissions.'
            ));
            return false;
        }

        savePageState();

        if (selectedIds.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Please select at least one property.'
            ));
            return false;
        }

        Savepoint sp = Database.setSavepoint();

        try {
            List<Property__c> records = [
                SELECT Id, Name, Status__c, Sales_Price__c,
                       Sale_Date__c, Agent__c,
                       Agent_Commission_Percentage__c,
                       Agent_Commission_Amount__c,
                       Sales_Office__r.Sales_Region__c
                FROM Property__c
                WHERE Id IN :selectedIds
                FOR UPDATE
            ];

            if (records.size() != selectedIds.size()) {
                throw new ApprovalException(
                    'One or more selected properties could not be found.'
                );
            }

            for (Property__c p : records) {

                if (p.Status__c != 'Closed Pending Approval') {
                    throw new ApprovalException(
                        p.Name + ' is no longer pending approval.'
                    );
                }

                if (p.Sales_Office__r.Sales_Region__c != regionId) {
                    throw new ApprovalException(
                        p.Name + ' does not belong to this region.'
                    );
                }

                if (p.Agent__c == null) {
                    throw new ApprovalException(
                        p.Name + ' does not have an Agent assigned.'
                    );
                }

                if (p.Sales_Price__c == null) {
                    throw new ApprovalException(
                        p.Name + ' does not have a Sales Price.'
                    );
                }

                Decimal pct = percentageByPropertyId.containsKey(p.Id)
                    ? percentageByPropertyId.get(p.Id)
                    : p.Agent_Commission_Percentage__c;

                if (pct == null || pct < 0 || pct > 100) {
                    throw new ApprovalException(
                        'Enter a valid commission percentage from 0% to 100% for ' +
                        p.Name + '.'
                    );
                }

                p.Agent_Commission_Percentage__c = pct;

                p.Agent_Commission_Amount__c =
                    p.Sales_Price__c * 0.03 * (pct / 100);

                p.Status__c = 'Closed Approved';
            }

            update records;

            selectedIds.clear();
            percentageByPropertyId.clear();

            pageNumber = 1;
            loadProperties();

            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                'Selected commissions have been approved successfully.'
            ));

            return true;

        } catch (Exception e) {
            Database.rollback(sp);

            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Approval failed: ' + e.getMessage()
            ));

            return false;
        }
    }

    public PageReference cancel() {
        if (regionId != null) {
            return new PageReference('/' + regionId);
        }

        return new PageReference(
            '/lightning/o/Sales_Region__c/list'
        );
    }

    public class PropertyRow {
        public Property__c propertyRecord { get; set; }
        public Boolean selected { get; set; }

        public PropertyRow() {
            selected = false;
        }
    }

    public class ApprovalException extends Exception {}
}