import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["fileInput", "fileList", "uploadButton"];

  connect() {
    this.attachedFiles = [];
  }

  accumulateAttachments() {
    this.attachedFiles = this.attachedFiles.concat(Array.from(this.fileInputTarget.files));
    this.updateFileList();
    this.fileInputTarget.value = ''; // Reset the file input value to allow re-selecting the same file
  }

  submitForm(event) {
    event.preventDefault();

    const dataTransfer = new DataTransfer();
    this.attachedFiles.forEach(file => { dataTransfer.items.add(file); });

    this.fileInputTarget.files = dataTransfer.files;
    this.element.submit();
  }

  removeFile(file) {
    this.attachedFiles = this.attachedFiles.filter(f => f !== file);
    this.updateFileList();
  }

  updateFileList() {
    this.fileListTarget.innerHTML = ''; // Clear the current file list

    if (this.attachedFiles.length) {
      const fileItems = this.attachedFiles.map((file) => this.createFileElement(file));
      fileItems.forEach((fileItem) => { this.fileListTarget.appendChild(fileItem) });
    } else {
      this.fileListTarget.innerHTML = `<li>none</li>`;
    }
    this.toggleUploadButton();
  }

  toggleUploadButton() {
    if (this.attachedFiles.length) {
      this.uploadButtonTarget.removeAttribute('disabled');
    } else {
      this.uploadButtonTarget.setAttribute('disabled', 'disabled');
    }
  }

  createFileElement(file) {
    const fileItem = document.createElement('li');
    fileItem.classList.add('d-flex');

    const fileNameSpan = document.createElement('span');
    fileNameSpan.classList.add('mr-2');
    fileNameSpan.textContent = file.name;

    const removeSpan = document.createElement('span');
    removeSpan.classList.add('remove-file');

    const dismissIconDiv = document.createElement('div');
    dismissIconDiv.classList.add('dismiss-icon');
    dismissIconDiv.setAttribute('alt', 'Remove');
    dismissIconDiv.innerHTML = '&nbsp;';

    const srOnlySpan = document.createElement('span');
    srOnlySpan.classList.add('sr-only');
    srOnlySpan.textContent = 'Remove';

    removeSpan.appendChild(dismissIconDiv);
    removeSpan.appendChild(srOnlySpan);
    removeSpan.appendChild(document.createTextNode('Remove'));

    removeSpan.addEventListener('click', () => {
      this.removeFile(file);
    });

    fileItem.appendChild(fileNameSpan);
    fileItem.appendChild(removeSpan);

    return fileItem;
  }
}