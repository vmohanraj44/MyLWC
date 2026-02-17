/**
 * @description Service to call BatchData Property Search API and map results to DTOs.
 * @author Agentforce
 * @date 2026-02-15
 * @group Integration
 */
public with sharing class BatchData_PropertySearchService {
    public class SearchRequest {
        @AuraEnabled public String city;
        @AuraEnabled public String state; // 2-letter
        @AuraEnabled public String zip;
        @AuraEnabled public Integer minBedrooms;
        @AuraEnabled public Integer maxBedrooms;
        @AuraEnabled public Integer minBathrooms;
        @AuraEnabled public Integer maxBathrooms;
        @AuraEnabled public Integer minSqft;
        @AuraEnabled public Integer maxSqft;

        public Map<String, Object> toPayload() {
            Map<String, Object> body = new Map<String, Object>();
            if (String.isNotBlank(city)) body.put('property_city', city);
            if (String.isNotBlank(state)) body.put('property_state', state);
            if (String.isNotBlank(zip)) body.put('property_zip', zip);
            if (minBedrooms != null) body.put('min_bedrooms', minBedrooms);
            if (maxBedrooms != null) body.put('max_bedrooms', maxBedrooms);
            if (minBathrooms != null) body.put('min_bathrooms', minBathrooms);
            if (maxBathrooms != null) body.put('max_bathrooms', maxBathrooms);
            if (minSqft != null) body.put('min_sqft', minSqft);
            if (maxSqft != null) body.put('max_sqft', maxSqft);
            return body;
        }
    }

    public class PropertyRowDTO {
        @AuraEnabled public String externalId;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String zip;
        @AuraEnabled public Integer bedrooms;
        @AuraEnabled public Decimal bathrooms;
        @AuraEnabled public Integer livingSqft;
        @AuraEnabled public Integer yearBuilt;
        @AuraEnabled public Integer lotSizeSqft;
        @AuraEnabled public Decimal estimatedValue;
        @AuraEnabled public Decimal priceRangeMin;
        @AuraEnabled public Decimal priceRangeMax;
        @AuraEnabled public Decimal lastSalePrice;
        @AuraEnabled public Date lastSaleDate;
        @AuraEnabled public Integer lienCount;
        @AuraEnabled public Decimal totalOpenLienBalance;
    }

    public class SearchResponse {
        @AuraEnabled public List<PropertyRowDTO> rows;
        public SearchResponse() { rows = new List<PropertyRowDTO>(); }
    }

    public class BatchDataException extends Exception {}

    // Named Credential name to be configured post-deploy
    public static final String NAMED_CREDENTIAL = 'BatchData_NC';
    // Base path for property search per documentation
    public static final String SEARCH_PATH = '/v1/properties/search';

    /**
     * @description Executes property search against BatchData and returns normalized DTOs.
     * @param req SearchRequest containing filters
     * @return SearchResponse
     * @throws BatchDataException for HTTP and parsing issues
     */
    @AuraEnabled
    public static SearchResponse searchProperties(SearchRequest req) {
        if (req == null) {
            throw new BatchDataException('Request cannot be null');
        }
        // Basic validation: require (city+state) or zip
        // Adding debug logging to help identify the issue with parameter passing
        System.debug('DEBUG: Search request received - City: ' + req.city + ', State: ' + req.state + ', Zip: ' + req.zip);
        Boolean hasCityState = String.isNotBlank(req.city) && String.isNotBlank(req.state);
        Boolean hasZip = String.isNotBlank(req.zip);
        if (!hasCityState && !hasZip) {
            throw new BatchDataException('Provide Zip or City and State');
        }

        Http http = new Http();
        HttpRequest httpReq = new HttpRequest();
        httpReq.setMethod('POST');
        // Using Named Credential for host + auth
        httpReq.setEndpoint('callout:' + NAMED_CREDENTIAL + SEARCH_PATH);
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setHeader('Accept', 'application/json');

        String body = JSON.serialize(req.toPayload());
        httpReq.setBody(body);

        try {
            HttpResponse res = http.send(httpReq);
            Integer status = res.getStatusCode();
            if (status == 200) {
                return parseSearchResponse(res.getBody());
            } else if (status == 204) {
                return new SearchResponse(); // no content
            } else if (status == 400 || status == 404) {
                // treat as no results or bad input
                return new SearchResponse();
            } else {
                throw new BatchDataException('BatchData API error: ' + status + ' - ' + res.getStatus());
            }
        } catch (System.CalloutException ex) {
            throw new BatchDataException('Callout failed: ' + ex.getMessage());
        }
    }

    private static SearchResponse parseSearchResponse(String raw) {
        SearchResponse sr = new SearchResponse();
        if (String.isBlank(raw)) return sr;

        // The API returns a JSON with records list and various datasets.
        // We will be defensive and pull fields if present.
        Object parsed = JSON.deserializeUntyped(raw);
        if (!(parsed instanceof Map<String, Object>)) return sr;

        Map<String, Object> root = (Map<String, Object>) parsed;
        
        // Handle the new API response structure
        List<Object> records = new List<Object>();
        if (root.containsKey('results') && root.get('results') instanceof Map<String, Object>) {
            Map<String, Object> results = (Map<String, Object>) root.get('results');
            if (results.containsKey('properties') && results.get('properties') instanceof List<Object>) {
                records = (List<Object>) results.get('properties');
            }
        } else if (root.containsKey('properties') && root.get('properties') instanceof List<Object>) {
            records = (List<Object>) root.get('properties');
        } else if (root.containsKey('data') && root.get('data') instanceof List<Object>) {
            records = (List<Object>) root.get('data');
        } else {
            // Some endpoints might return the array directly
            if (parsed instanceof List<Object>) {
                records = (List<Object>) parsed;
            } else {
                records = new List<Object>();
            }
        }

        for (Object recObj : records) {
            if (!(recObj instanceof Map<String, Object>)) continue;
            Map<String, Object> rec = (Map<String, Object>) recObj;
            PropertyRowDTO row = new PropertyRowDTO();

            // Id - using _id from the new response
            row.externalId = (String) rec.get('_id');

            // Address
            Map<String, Object> address = (Map<String, Object>) rec.get('address');
            if (address != null) {
                row.street = str(address.get('street'));
                row.city = str(address.get('city'));
                row.state = str(address.get('state'));
                row.zip = str(address.get('zip'));
            }

            // Building - using listing section from new response
            Map<String, Object> listing = (Map<String, Object>) rec.get('listing');
            if (listing != null) {
                row.livingSqft = toInt(listing.get('totalBuildingAreaSquareFeet'));
                row.bedrooms = toInt(listing.get('bedroomCount'));
                row.bathrooms = toDecimal(listing.get('bathroomCount'));
                row.yearBuilt = toInt(listing.get('yearBuilt'));
                row.lotSizeSqft = toInt(listing.get('lotSizeSquareFeet'));
            }

            // Valuation
            Map<String, Object> valuation = (Map<String, Object>) rec.get('valuation');
            if (valuation != null) {
                row.estimatedValue = toDecimal(valuation.get('estimatedValue'));
                row.priceRangeMin = toDecimal(valuation.get('priceRangeMin'));
                row.priceRangeMax = toDecimal(valuation.get('priceRangeMax'));
            }

            // Sale / Deed - using priorSale from sale section
            Map<String, Object> sale = (Map<String, Object>) rec.get('sale');
            if (sale != null) {
                Map<String, Object> priorSale = (Map<String, Object>) sale.get('priorSale');
                if (priorSale != null) {
                    Map<String, Object> mortgages = (Map<String, Object>) priorSale.get('mortgages');
                    if (mortgages != null && mortgages.containsKey('documentNumber')) {
                        // Get the first mortgage if available
                        row.lastSalePrice = toDecimal(mortgages.get('loanAmount'));
                    }
                }
            }

            // Mortgage / Liens - using openLien section
            Map<String, Object> openLien = (Map<String, Object>) rec.get('openLien');
            if (openLien != null) {
                row.lienCount = toInt(openLien.get('totalOpenLienCount'));
            }

            // Additional fields from new response
            Map<String, Object> mortgageliens = (Map<String, Object>) rec.get('mortgageHistory');
            if (mortgageliens != null && mortgageliens.containsKey('totalOpenLienBalance')) {
                row.totalOpenLienBalance = toDecimal(mortgageliens.get('totalOpenLienBalance'));
            }

            sr.rows.add(row);
        }
        return sr;
    }

    private static String str(Object o) { return o == null ? null : String.valueOf(o); }
    private static Integer toInt(Object o) {
        if (o == null) return null;
        try { return Integer.valueOf(String.valueOf(o).replaceAll('[^0-9-]', '')); } catch (Exception e) { return null; }
    }
    private static Decimal toDecimal(Object o) {
        if (o == null) return null;
        try { return Decimal.valueOf(String.valueOf(o).replaceAll('[^0-9\\.-]', '')); } catch (Exception e) { return null; }
    }
    private static Date toDate(Object o) {
        if (o == null) return null;
        try { return Date.valueOf(String.valueOf(o).substring(0, 10)); } catch (Exception e) { return null; }
    }
}
