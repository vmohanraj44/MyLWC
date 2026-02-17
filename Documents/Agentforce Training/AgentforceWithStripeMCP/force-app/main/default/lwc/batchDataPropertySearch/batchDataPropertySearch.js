import { LightningElement, track } from 'lwc';
import search from '@salesforce/apex/BatchData_PropertyController.search';
import saveResults from '@salesforce/apex/BatchData_PropertyController.saveResults';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BatchDataPropertySearch extends LightningElement {
    // Inputs
    @track city = '';
    @track state = '';
    @track zip = '';
    @track minBedrooms;
    @track maxBedrooms;
    @track minBathrooms;
    @track maxBathrooms;
    @track minSqft;
    @track maxSqft;

    // UI state
    @track isLoading = false;
    @track rows = [];

    columns = [
        { label: 'Street', fieldName: 'street', type: 'text' },
        { label: 'City', fieldName: 'city', type: 'text' },
        { label: 'State', fieldName: 'state', type: 'text' },
        { label: 'Zip', fieldName: 'zip', type: 'text' },
        { label: 'Beds', fieldName: 'bedrooms', type: 'number' },
        { label: 'Baths', fieldName: 'bathrooms', type: 'number' },
        { label: 'Sqft', fieldName: 'livingSqft', type: 'number' },
        { label: 'Year', fieldName: 'yearBuilt', type: 'number' },
        { label: 'Lot Sqft', fieldName: 'lotSizeSqft', type: 'number' },
        { label: 'Est. Value', fieldName: 'estimatedValue', type: 'currency' },
        { label: 'Last Sale Price', fieldName: 'lastSalePrice', type: 'currency' },
        { label: 'Lien Count', fieldName: 'lienCount', type: 'number' },
        { label: 'Open Lien Balance', fieldName: 'totalOpenLienBalance', type: 'currency' }
    ];

    get hasResults() {
        return this.rows && this.rows.length > 0;
    }
    get showEmpty() {
        return !this.isLoading && (!this.rows || this.rows.length === 0);
    }
    get isSearchDisabled() {
        const hasCityState = this.city?.trim() && this.state?.trim();
        const hasZip = this.zip?.trim();
        return !(hasCityState || hasZip);
    }
    get isSaveDisabled() {
        return !this.hasResults;
    }

    handleCityChange = (e) => { this.city = e.target.value; };
    handleStateChange = (e) => { this.state = (e.target.value || '').toUpperCase(); };
    handleZipChange = (e) => { this.zip = e.target.value; };

    handleNumberChange(e, field) {
        const v = e.target.value;
        this[field] = v === '' || v === null || v === undefined ? undefined : Number(v);
    }

    buildRequest() {
        // Debug log to see what values are being passed
        console.log('Building request with:', {
            city: this.city,
            state: this.state,
            zip: this.zip,
            minBedrooms: this.minBedrooms,
            maxBedrooms: this.maxBedrooms,
            minBathrooms: this.minBathrooms,
            maxBathrooms: this.maxBathrooms,
            minSqft: this.minSqft,
            maxSqft: this.maxSqft
        });
        
        return {
            city: this.city || null,
            state: this.state || null,
            zip: this.zip || null,
            minBedrooms: this.minBedrooms,
            maxBedrooms: this.maxBedrooms,
            minBathrooms: this.minBathrooms,
            maxBathrooms: this.maxBathrooms,
            minSqft: this.minSqft,
            maxSqft: this.maxSqft
        };
    }

    async handleSearch() {
        if (this.isSearchDisabled) return;
        this.isLoading = true;
        try {
            const req = this.buildRequest();
            const resp = await search({ req });
            this.rows = (resp && resp.rows) ? resp.rows : [];
        } catch (e) {
            this.rows = [];
            this.dispatchEvent(new ShowToastEvent({
                title: 'Search failed',
                message: e?.body?.message || e?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleSave() {
        if (this.isSaveDisabled) return;
        this.isLoading = true;
        try {
            const req = this.buildRequest();
            const result = await saveResults({ req, rows: this.rows });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved',
                message: `Search ${result.searchId}. Properties: +${result.propertiesInserted} / ~${result.propertiesUpdated}. Mortgages: ${result.mortgagesUpserted}.`,
                variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Save failed',
                message: e?.body?.message || e?.message || 'Unknown error',
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }
}
