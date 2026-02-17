/**
 * @description Unit tests for BatchData integration: service and controller.
 * - Covers callout success and error using HttpCalloutMock
 * - Covers saveResults DML flow and permissioned operations
 */
@IsTest
private class BatchData_PropertyTests {
    // Simple mock for the property search API
    private class PropertySearchMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        PropertySearchMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            System.assertEquals('POST', req.getMethod(), 'Method should be POST');
            // Updated endpoint check to account for Named Credential prefix
            System.assert(req.getEndpoint().contains('callout:' + BatchData_PropertySearchService.NAMED_CREDENTIAL + BatchData_PropertySearchService.SEARCH_PATH), 'Endpoint must include search path');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    // Minimal payload with two properties including valuation/sale/mortgage in new format
    private static String sampleSuccessBody() {
        return JSON.serialize(new Map<String, Object>{
            'results' => new Map<String, Object>{
                'properties' => new List<Object>{
                    new Map<String, Object>{
                        '_id' => 'prop-1',
                        'address' => new Map<String, Object>{
                            'street' => '123 Main St',
                            'city' => 'Phoenix',
                            'state' => 'AZ',
                            'zip' => '85001'
                        },
                        'listing' => new Map<String, Object>{
                            'totalBuildingAreaSquareFeet' => 1500,
                            'bedroomCount' => 3,
                            'bathroomCount' => 2,
                            'yearBuilt' => 1995,
                            'lotSizeSquareFeet' => 6000
                        },
                        'valuation' => new Map<String, Object>{
                            'estimatedValue' => 400000,
                            'priceRangeMin' => 380000,
                            'priceRangeMax' => 420000
                        },
                        'sale' => new Map<String, Object>{
                            'priorSale' => new Map<String, Object>{
                                'mortgages' => new Map<String, Object>{
                                    'loanAmount' => 350000
                                }
                            }
                        },
                        'openLien' => new Map<String, Object>{
                            'totalOpenLienCount' => 1
                        }
                    },
                    new Map<String, Object>{
                        '_id' => 'prop-2',
                        'address' => new Map<String, Object>{
                            'street' => '456 Oak Ave',
                            'city' => 'Phoenix',
                            'state' => 'AZ',
                            'zip' => '85001'
                        },
                        'listing' => new Map<String, Object>{
                            'totalBuildingAreaSquareFeet' => 1800,
                            'bedroomCount' => 4,
                            'bathroomCount' => 3,
                            'yearBuilt' => 2005,
                            'lotSizeSquareFeet' => 7200
                        },
                        'valuation' => new Map<String, Object>{
                            'estimatedValue' => 500000,
                            'priceRangeMin' => 480000,
                            'priceRangeMax' => 520000
                        },
                        'sale' => new Map<String, Object>{
                            'priorSale' => new Map<String, Object>{
                                'mortgages' => new Map<String, Object>{
                                    'loanAmount' => 410000
                                }
                            }
                        },
                        'openLien' => new Map<String, Object>{
                            'totalOpenLienCount' => 2
                        }
                    }
                }
            }
        });
    }

    @IsTest
    static void testSearchSuccess() {
        Test.setMock(HttpCalloutMock.class, new PropertySearchMock(200, sampleSuccessBody()));
        BatchData_PropertySearchService.SearchRequest req = new BatchData_PropertySearchService.SearchRequest();
        req.city = 'Phoenix';
        req.state = 'AZ';

        Test.startTest();
        BatchData_PropertySearchService.SearchResponse resp = BatchData_PropertySearchService.searchProperties(req);
        Test.stopTest();

        System.assertNotEquals(null, resp, 'Response should not be null');
        System.assertEquals(2, resp.rows.size(), 'Expect two rows');
        System.assertEquals('123 Main St', resp.rows[0].street);
        System.assertEquals(3, resp.rows[0].bedrooms);
        System.assertEquals(1, resp.rows[0].lienCount);
    }

    @IsTest
    static void testSearchBadInputHandled() {
        // API returns 400 -> treated as empty results
        Test.setMock(HttpCalloutMock.class, new PropertySearchMock(400, '{"message":"bad request"}'));
        BatchData_PropertySearchService.SearchRequest req = new BatchData_PropertySearchService.SearchRequest();
        req.zip = '85001';

        Test.startTest();
        BatchData_PropertySearchService.SearchResponse resp = BatchData_PropertySearchService.searchProperties(req);
        Test.stopTest();

        System.assertNotEquals(null, resp, 'Response should not be null');
        System.assertEquals(0, resp.rows.size(), 'Expect zero rows on bad request');
    }

    @IsTest
    static void testControllerSaveFlow() {
        Test.setMock(HttpCalloutMock.class, new PropertySearchMock(200, sampleSuccessBody()));
        // Build a request and get rows
        BatchData_PropertySearchService.SearchRequest req = new BatchData_PropertySearchService.SearchRequest();
        req.city = 'Phoenix';
        req.state = 'AZ';

        BatchData_PropertySearchService.SearchResponse sr = BatchData_PropertySearchService.searchProperties(req);
        System.assert(sr.rows.size() > 0, 'Should have rows to save');

        Test.startTest();
        BatchData_PropertyController.SaveResultDTO res = BatchData_PropertyController.saveResults(req, sr.rows);
        Test.stopTest();

        System.assertNotEquals(null, res.searchId, 'Search Id should be returned');
        System.assert(res.propertiesInserted > 0, 'Should insert property records');

        // Verify properties linked to search
        List<Property__c> props = [
            SELECT Id, Search__c, External_Id__c, Street__c, Estimated_Value__c
            FROM Property__c WHERE Search__c = :res.searchId
        ];
        System.assertEquals(sr.rows.size(), props.size(), 'All returned rows should be saved as properties');

        // Verify mortgages created
        Integer mortgageCount = [SELECT COUNT() FROM Mortgage__c WHERE Property__c IN :props];
        System.assertEquals(mortgageCount, sr.rows.size(), 'One mortgage per property expected');
    }
}
