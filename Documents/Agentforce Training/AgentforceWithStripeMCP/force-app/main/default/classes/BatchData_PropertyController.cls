/**
 * @description AuraEnabled controller for LWC to search BatchData properties and save to Salesforce.
 * Applies with sharing, user-mode DML where applicable, and DTO-based IO.
 */
public with sharing class BatchData_PropertyController {
    public class SaveResultDTO {
        @AuraEnabled public Id searchId;
        @AuraEnabled public Integer propertiesInserted;
        @AuraEnabled public Integer propertiesUpdated;
        @AuraEnabled public Integer mortgagesUpserted;
    }

    /**
     * Proxy to service for property search.
     */
    @AuraEnabled(cacheable=false)
    public static BatchData_PropertySearchService.SearchResponse search(BatchData_PropertySearchService.SearchRequest req) {
        return BatchData_PropertySearchService.searchProperties(req);
    }

    /**
     * Persist a search session and its result rows.
     * - Creates Property_Search__c
     * - Upserts Property__c by External_Id__c and links to search
     * - Upserts/Creates Mortgage__c summary per property
     */
    @AuraEnabled
    public static SaveResultDTO saveResults(BatchData_PropertySearchService.SearchRequest req, List<BatchData_PropertySearchService.PropertyRowDTO> rows) {
        if (req == null) {
            throw new AuraHandledException('Request cannot be null');
        }
        if (rows == null) {
            rows = new List<BatchData_PropertySearchService.PropertyRowDTO>();
        }

        // Create search record
        Property_Search__c search = new Property_Search__c();
        search.Search_City__c = req.city;
        search.Search_State__c = req.state;
        search.Search_Zip__c = req.zip;
        search.Performed_On__c = System.now();
        search.Result_Count__c = rows.size();
        // Serialize filters for traceability
        search.Filters_JSON__c = JSON.serialize(req.toPayload());

        // Insert search in user mode
        Database.SaveResult sr = Database.insert(search, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            throw new AuraHandledException('Failed to create search record');
        }
        Id searchId = sr.getId();

        // Prepare Properties upsert by External_Id__c
        List<Property__c> upserts = new List<Property__c>();
        for (BatchData_PropertySearchService.PropertyRowDTO r : rows) {
            Property__c p = new Property__c();
            p.External_Id__c = r.externalId;
            // Name fallback to Street, City
            p.Name = (r.street != null ? r.street : 'Property') + (r.city != null ? ' - ' + r.city : '');
            p.Street__c = r.street;
            p.City__c = r.city;
            p.State__c = r.state;
            p.Zip__c = r.zip;
            p.Living_Sqft__c = r.livingSqft;
            p.Bedrooms__c = r.bedrooms;
            p.Bathrooms__c = r.bathrooms;
            p.Year_Built__c = r.yearBuilt;
            p.Lot_Size_Sqft__c = r.lotSizeSqft;
            p.Estimated_Value__c = r.estimatedValue;
            p.Price_Range_Min__c = r.priceRangeMin;
            p.Price_Range_Max__c = r.priceRangeMax;
            p.Last_Sale_Price__c = r.lastSalePrice;
            p.Last_Sale_Date__c = r.lastSaleDate;
            p.Search__c = searchId;
            upserts.add(p);
        }

        Integer created = 0, updated = 0;
        if (!upserts.isEmpty()) {
            // Upsert by External_Id__c in user mode
            Database.UpsertResult[] urs = Database.upsert(upserts, Property__c.Fields.External_Id__c, AccessLevel.USER_MODE);
            for (Database.UpsertResult ur : urs) {
                if (ur.isSuccess()) {
                    if (ur.isCreated()) created++;
                    else updated++;
                } else {
                    // Collect first error (could extend to full aggregation)
                    Database.Error e = ur.getErrors().isEmpty() ? null : ur.getErrors()[0];
                    throw new AuraHandledException('Property upsert failed: ' + (e != null ? e.getMessage() : 'unknown'));
                }
            }
        }

        // Map externalId to Property Id to relate Mortgage
        Map<String, Id> extIdToPropId = new Map<String, Id>();
        for (Property__c p : [SELECT Id, External_Id__c FROM Property__c WHERE Search__c = :searchId WITH USER_MODE]) {
            if (p.External_Id__c != null) extIdToPropId.put(p.External_Id__c, p.Id);
        }

        // Upsert or insert mortgage summaries
        List<Mortgage__c> mortgageUpserts = new List<Mortgage__c>();
        for (BatchData_PropertySearchService.PropertyRowDTO r : rows) {
            Id propId = r.externalId != null ? extIdToPropId.get(r.externalId) : null;
            if (propId == null) continue;

            Mortgage__c m = new Mortgage__c();
            m.Property__c = propId;
            m.Lien_Count__c = r.lienCount;
            m.Total_Open_Lien_Balance__c = r.totalOpenLienBalance;
            mortgageUpserts.add(m);
        }

        Integer mortgageCount = 0;
        if (!mortgageUpserts.isEmpty()) {
            // No external ID on Mortgage; use insert for new summaries
            Database.SaveResult[] mrs = Database.insert(mortgageUpserts, AccessLevel.USER_MODE);
            for (Database.SaveResult r : mrs) {
                if (r.isSuccess()) mortgageCount++;
                else {
                    Database.Error e = r.getErrors().isEmpty() ? null : r.getErrors()[0];
                    throw new AuraHandledException('Mortgage insert failed: ' + (e != null ? e.getMessage() : 'unknown'));
                }
            }
        }

        SaveResultDTO result = new SaveResultDTO();
        result.searchId = searchId;
        result.propertiesInserted = created;
        result.propertiesUpdated = updated;
        result.mortgagesUpserted = mortgageCount;
        return result;
    }
}
