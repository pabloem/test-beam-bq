#!/bin/sh

BASE_NUMBER=$RANDOM
GCP_PROJECT=noogler-projects
TOPIC_NAME=test_bq_throughput_082020_$BASE_NUMBER
JOB_NAME=test-bq-throughput-dataflow-08-2020-$BASE_NUMBER
GCS_BUCKET=gs://noogler-projects.appspot.com/bqtest08_2020_$BASE_NUMBER/
BQ_DATASET=bigquery_perf_08_2020
BQ_TABLE=test_$BASE_NUMBER

EXPECTED_QPS=100000
GENERATOR_SCHEMA_FILE=generator_json_schema

SCHEMA_GCS_LOCATION=${GCS_BUCKET}${GENERATOR_SCHEMA_FILE}

echo "Topic name is ${TOPIC_NAME}"
echo "Dataflow job name is ${JOB_NAME}"
echo "GCS bucket is ${GCS_BUCKET}"
echo

echo "Copying Schema file to GCS bucket"
gsutil cp $GENERATOR_SCHEMA_FILE $SCHEMA_GCS_LOCATION
echo "copied."
echo

echo Creating Pubsub topic
gcloud pubsub topics create --project=$GCP_PROJECT $TOPIC_NAME

FULL_TOPIC_NAME=projects/$GCP_PROJECT/topics/$TOPIC_NAME
echo "Topic CREATED."
echo

echo Launching data generator job
gcloud beta dataflow flex-template run $JOB_NAME \
	--project=$GCP_PROJECT \
	--region=us-central1 \
	--template-file-gcs-location=gs://dataflow-templates/latest/flex/Streaming_Data_Generator \
	--parameters schemaLocation=$SCHEMA_GCS_LOCATION,topic=$FULL_TOPIC_NAME,qps=$EXPECTED_QPS,maxNumWorkers=100
echo Job launched
echo

echo "Launching job writing to BigQuery"
python -m apache_beam.io.gcp.bigquery_pabloem_perf \
    --test-pipeline-options="
    --streaming
    --autoscaling_algorithm=THROUGHPUT_BASED
    --max_num_workers=30
    --timeout_ms=30000
    --runner=TestDataflowRunner
    --project=${GCP_PROJECT}
    --region=us-central1
    --staging_location=${GCS_BUCKET}/staging/
    --temp_location=${GCS_BUCKET}/temp/
    --sdk_location=beam/sdks/python/dist/apache-beam-2.24.0.dev0.tar.gz
    --topic=${FULL_TOPIC_NAME}
    --output_dataset=${BQ_DATASET}
    --output_table=${BQ_TABLE}
    --input_options={}"
echo "Launched"
echo


### NOW WE WRAP EVERYTHING UP
echo gsutil rm -rf $GCS_BUCKET > cleanup_script.sh
echo bq --project_id=$GCP_PROJECT rm -f $BQ_DATASET.$BQ_TABLE >> cleanup_script.sh
echo "gcloud dataflow jobs list --project=noogler-projects --limit=2 --uri | xargs gcloud dataflow jobs cancel" >> cleanup_script.sh
echo gcloud pubsub topics delete $FULL_TOPIC_NAME >> cleanup_script.sh
