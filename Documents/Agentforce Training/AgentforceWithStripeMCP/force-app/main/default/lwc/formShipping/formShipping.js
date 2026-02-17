import { LightningElement, api, track } from 'lwc';

/**
 * FormShipping LWC
 * - Implements a SLDS-styled "Form Shipping" UI per Figma spec
 * - LDS-first: purely client UI; no direct Apex calls
 * - Accessibility: labeled controls, proper semantics
 */
export default class FormShipping extends LightningElement {
    // Exposed public @api properties so the template can bind and Flows/App Builder can pass defaults
    @api fullName = '';
    @api location = '';
    @api deliveryNote = '';
    @api acceptTerms = false;
    @track _internal = {};

    // Example options to mirror a "Location" select from the Figma design
    get locationOptions() {
        return [
            { label: 'Warehouse A', value: 'warehouseA' },
            { label: 'Warehouse B', value: 'warehouseB' },
            { label: 'Warehouse C', value: 'warehouseC' }
        ];
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (!field) return;

        switch (field) {
            case 'fullName':
                this.fullName = value;
                break;
            case 'location':
                this.location = value;
                break;
            case 'deliveryNote':
                this.deliveryNote = value;
                break;
            default:
                break;
        }
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        if (field === 'acceptTerms') {
            this.acceptTerms = event.target.checked;
        }
    }

    get isSaveDisabled() {
        // Disable if critical inputs missing or terms not accepted
        return !this.fullName || !this.location || !this.acceptTerms;
    }

    // Expose value-change events compatible with Flow screen components
    renderedCallback() {
        // No-op: hook reserved for future sync with lightning-input-field if used with record forms
    }

    handleSave() {
        // In a real flow, this could emit an event or integrate with a parent/flow
        const detail = {
            fullName: this.fullName,
            location: this.location,
            deliveryNote: this.deliveryNote,
            acceptTerms: this.acceptTerms
        };
        this.dispatchEvent(new CustomEvent('saveshipping', { detail, bubbles: true, composed: true }));
    }
}
