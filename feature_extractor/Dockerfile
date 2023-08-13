FROM python:3.11.4

# install sentence-transformers with cpu only
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
RUN pip install transformers tqdm numpy scikit-learn scipy nltk sentencepiece
RUN pip install --no-deps sentence-transformers 

RUN pip install fastapi uvicorn

COPY server.py .

CMD python server.py

EXPOSE 9294